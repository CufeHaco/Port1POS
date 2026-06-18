# boot.rb - Dynamic array-based boot for Port1POS
# Following Cufe style: Build compact state (arrays) → Match patterns (string/index) → Verify gates → Execute fast path or fallback
# Dynamic discovery via array pipelines, no rigid trees. Self-documenting pipeline.

require 'pathname'

module Port1POS
  class Boot
    # Compact component index as array of hashes (easy to extend, pattern-matchable)
    # Add new components here as we build downward (micro_ipc, print_server, dbf_compat, register_loop, etc.)
    COMPONENT_INDEX = [
      { name: :micro_ipc,       path: 'micro_ipc.rb',                        required: true,  layer: :core },
      { name: :print_server,    path: 'lib/compatibility/print_server.rb',   required: false, layer: :compatibility },
      # Future: { name: :dbf_compat, path: 'lib/compatibility/dbf_reader.rb', required: false, layer: :compatibility },
      #         { name: :register,   path: 'lib/register/transaction_loop.rb', required: true,  layer: :register },
    ].freeze

    # Main entry: Boot.boot!(options)
    # options[:base_dir] to override root
    def self.boot!(options = {})
      state = build_state(options)
      runtime = match_runtime(state)
      verified = verify_components(state, runtime)
      execute!(state, verified, runtime)
    end

    private_class_method def self.build_state(options)
      # BUILD phase: compact array-based state representation
      base_dir = options[:base_dir] || Pathname.new(__dir__)
      {
        base_dir: base_dir,
        components: COMPONENT_INDEX.dup,  # working copy of the array
        loaded: [],
        errors: [],
        options: options
      }
    end

    private_class_method def self.match_runtime(_state)
      # MATCH phase: fast runtime classification via pattern checks (string/index matching)
      is_jruby = defined?(JRUBY_VERSION)
      ruby_version = RUBY_VERSION
      os = RbConfig::CONFIG['host_os']

      {
        jruby: is_jruby,
        ruby_version: ruby_version,
        os: os,
        windows: !!(os =~ /mswin|mingw|cygwin/),
        linux: !!(os =~ /linux|darwin/),  # darwin for mac dev too
        # Expand with bit flags later if needed for capability masks
      }
    end

    private_class_method def self.verify_components(state, runtime)
      # VERIFY phase: gates and status before any execution
      verified = state[:components].map do |comp|
        full_path = state[:base_dir] / comp[:path]
        exists = full_path.exist?

        status =
          if comp[:required] && !exists
            :missing_required
          elsif !exists
            :optional_missing
          else
            :ready
          end

        comp.merge(
          status: status,
          full_path: full_path,
          exists: exists
        )
      end

      # Gate: collect missing required (non-fatal here for early dev, logged clearly)
      missing = verified.select { |c| c[:status] == :missing_required }
      if missing.any?
        state[:errors] << "Missing required components: #{missing.map { |c| c[:name] }.join(', ')}"
      end

      verified
    end

    private_class_method def self.execute!(state, verified, runtime)
      # EXECUTE phase: load in defined order, with graceful fallbacks + reporting
      puts "[Port1POS::Boot] Starting dynamic boot (Build-Match-Verify-Execute pipeline)"
      puts "[Port1POS::Boot] Runtime: JRuby=#{runtime[:jruby]} | Ruby=#{runtime[:ruby_version]} | OS=#{runtime[:os]}"

      loaded_count = 0

      verified.each do |comp|
        case comp[:status]
        when :ready
          begin
            require comp[:full_path].to_s
            puts "  ✓ Loaded #{comp[:name]} (#{comp[:layer]})"
            loaded_count += 1
            state[:loaded] << comp[:name]
          rescue LoadError => e
            puts "  ✗ LoadError for #{comp[:name]}: #{e.message}"
            state[:errors] << "LoadError: #{comp[:name]}"
          rescue => e
            puts "  ✗ Error loading #{comp[:name]}: #{e.class} - #{e.message}"
            state[:errors] << "Error: #{comp[:name]} - #{e.message}"
          end
        when :optional_missing
          puts "  ○ Skipped optional #{comp[:name]} (file not present yet — graceful fallback)"
        when :missing_required
          puts "  ✗ FATAL: Required component #{comp[:name]} missing at #{comp[:full_path]}"
        end
      end

      puts "[Port1POS::Boot] Boot complete. Loaded #{loaded_count}/#{verified.size} components"
      unless state[:errors].empty?
        puts "[Port1POS::Boot] Errors/Warnings: #{state[:errors].join(' | ')}"
      end

      { verified: verified, runtime: runtime, loaded: state[:loaded], errors: state[:errors] }
    end
  end
end

# Convenience: allow `ruby boot.rb` for quick test / smoke
if __FILE__ == $0
  result = Port1POS::Boot.boot!
  puts "\n[Port1POS] Boot result keys: #{result.keys.inspect}"
  puts "[Port1POS] Loaded components: #{result[:loaded].inspect}"
end
