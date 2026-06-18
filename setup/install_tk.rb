#!/usr/bin/env ruby
# setup/install_tk.rb
# Port1POS Tk Installer — integrated version of Cufe's rubytk_patchV2
#
# Purpose: Ensure a working Ruby Tk (tk gem + Tcl/Tk 8.6) for the Port1POS GUI
# on Linux, macOS, and Windows.
#
# This is a direct integration + light adaptation of the rubytk_patchV2 installer
# into the Port1POS project so everything is self-contained.
#
# Style notes (cufe-ruby-coding-style influence):
# - Dynamic detection with arrays + pattern matching (glob, version checks)
# - Build state (paths, versions) → Match OS/version → Verify files → Execute install
# - Clear logging and graceful error paths with cleanup
#
# Run from Port1POS root:
#   ruby setup/install_tk.rb
#
# After success, you can run:
#   ruby lib/gui/tk_main.rb

require 'rbconfig'
require 'fileutils'

module Port1POS
  module Setup
    class TkInstaller
      def initialize
        @os = RbConfig::CONFIG['host_os']
        @tcltk_version = nil
        @supported_version = '8.6'
        @tcl_config_path = nil
        @tk_config_path = nil
        @tcl_lib_path = nil
        @tk_lib_path = nil
        @tcl_include_path = nil
        @tk_include_path = nil
        @log_file = 'tk_installer.log'
        @temp_log = 'tmp_apt_output'
        log "Starting Port1POS Tk Installer at #{Time.now} on #{@os}"
        log "Integrated from rubytk_patchV2 for self-contained Port1POS setup"
      end

      def log(message)
        File.open(@log_file, 'a') { |f| f.puts "[#{Time.now}] #{message}" }
        puts message
      end

      # Dynamic detection with array pipelines + fallback globs (cufe-style)
      def find_tcltk(file, search_paths)
        matches = search_paths.flat_map { |path| Dir.glob("#{path}/**/#{file}", File::FNM_CASEFOLD) }
        log "Glob matches for #{file}: #{matches.inspect}"

        if matches.empty?
          log "No initial matches. Falling back to full /usr glob..."
          matches = Dir.glob("/usr/**/#{file}", File::FNM_CASEFOLD)
        end

        if matches.empty? && @os !~ /mswin|mingw/
          log "Last-ditch system find..."
          system("find /usr -name '#{file}' 2>/dev/null > #{@temp_log}")
          matches = File.read(@temp_log).lines.map(&:chomp) rescue []
          File.delete(@temp_log) if File.exist?(@temp_log)
        end

        file_found = false
        matches.each do |found_path|
          next unless File.exist?(found_path)
          if found_path.match?(/#{@tcltk_version || @supported_version}\.?\d*/i)
            case file
            when "tclConfig.sh" then @tcl_config_path = File.dirname(found_path)
            when "tkConfig.sh"  then @tk_config_path  = File.dirname(found_path)
            when /libtcl.*\.so/ then @tcl_lib_path    = File.dirname(found_path)
            when /libtk.*\.so/  then @tk_lib_path     = File.dirname(found_path)
            when "tcl.h"        then @tcl_include_path = File.dirname(found_path)
            when "tk.h"        then @tk_include_path  = File.dirname(found_path)
            end
            log "Found #{file} at: #{found_path}"
            file_found = true
            break
          end
        end

        unless file_found
          log "File not found: #{file}"
          return false
        end
        true
      end

      def get_tcltk_version
        if system('which tclsh > /dev/null 2>&1')
          version = `tclsh -e 'puts [info patchlevel]'`.strip
          log "Detected Tcl/Tk version: #{version}"
          version
        else
          log "No tclsh found. Updating PATH..."
          system('export PATH=$PATH:/usr/bin') unless @os =~ /mswin|mingw/
          nil
        end
      end

      def check_requirements
        log "Checking requirements (Build phase)"
        unless system('which gem > /dev/null 2>&1')
          log 'Error: RubyGems not found.'
          cleanup_and_exit(1)
        end
        unless @os =~ /mswin|mingw/ || system('sudo -v > /dev/null 2>&1')
          log 'Error: sudo required for Linux/macOS.'
          cleanup_and_exit(1)
        end
        if @os =~ /linux/ && !system('which X > /dev/null 2>&1')
          log 'Warning: X11 not found. Tk needs a graphical environment.'
        end

        # JRuby note (Port1POS target)
        if defined?(JRUBY_VERSION)
          log "JRuby detected (#{JRUBY_VERSION}). Native Tk support is limited."
          log "The installer will try, but consider JavaFX/Swing fallback for full JRuby GUI later."
        end
      end

      def install_dependencies
        log "Installing Tcl/Tk #{@supported_version} dependencies (Execute phase)"
        case @os
        when /linux/
          system 'sudo apt-get update'
          cmd = "sudo apt-get install -y ruby-all-dev tcl#{@supported_version}-dev tk#{@supported_version}-dev libx11-dev > #{@temp_log} 2>&1"
          unless system(cmd)
            log "Installation failed."
            cleanup_and_exit(1)
          end
        when /darwin/
          if system('brew --version > /dev/null 2>&1')
            system("brew install tcl-tk@#{@supported_version}") or cleanup_and_exit(1)
          else
            log 'Homebrew not found. Install it or use ActiveTcl.'
            cleanup_and_exit(1)
          end
        when /mswin|mingw/
          log 'Windows: Please ensure ActiveTcl 8.6 is installed at C:/ActiveTcl'
          exit 1 unless Dir.exist?('C:/ActiveTcl')
          @tcl_config_path = @tcl_lib_path = @tcl_include_path = 'C:/ActiveTcl'
          @tk_config_path = @tk_lib_path = @tk_include_path = 'C:/ActiveTcl'
        else
          log "Unsupported OS: #{@os}"
          cleanup_and_exit(1)
        end
        @tcltk_version = get_tcltk_version&.split('.')&.slice(0..1)&.join('.') || @supported_version
      end

      def detect_tcltk
        log "Detecting Tcl/Tk (Match + Verify phase)"
        existing = get_tcltk_version
        if existing
          major_minor = existing.split('.')[0..1].join('.')
          if major_minor == @supported_version
            @tcltk_version = major_minor
          elsif major_minor.start_with?('9.')
            log "Tcl/Tk 9.x detected (not supported by tk gem 0.5.1). Installing 8.6..."
            install_dependencies
          else
            install_dependencies
          end
        else
          install_dependencies
        end

        search_paths = case @os
                       when /linux/
                         ["/usr/lib", "/usr/lib/\#{`uname -m`.strip}", "/usr/include", "/usr/share/tcltk"]
                       when /darwin/
                         ["/opt/homebrew/Cellar/tcl-tk@#{@tcltk_version}", "/usr/local/Cellar/tcl-tk", "/Library/Frameworks"]
                       when /mswin|mingw/
                         ['C:/ActiveTcl', 'C:/Tcl']
                       else
                         []
                       end

        tcltk_files = ["tclConfig.sh", "tkConfig.sh", "libtcl#{@tcltk_version}.so", "libtk#{@tcltk_version}.so", "tcl.h", "tk.h"]
        found_all = tcltk_files.all? { |f| find_tcltk(f, search_paths) }
        unless found_all
          log 'Some Tcl/Tk files still missing after detection.'
          cleanup_and_exit(1)
        end
      end

      def create_symlinks
        return unless @os =~ /linux/
        log "Creating symlinks for Tcl/Tk #{@tcltk_version}"
        symlinks = [
          ["#{@tcl_config_path}/tclConfig.sh", '/usr/lib/tclConfig.sh'],
          ["#{@tk_config_path}/tkConfig.sh", '/usr/lib/tkConfig.sh']
        ]
        symlinks.each do |src, dest|
          if File.exist?(src) && !File.exist?(dest)
            system("sudo ln -s #{src} #{dest}") or log "Failed symlink: #{src}"
          end
        end
      end

      def install_tk_gem
        log 'Installing tk gem (0.5.1) with platform flags'
        flags = case @os
                when /linux/
                  "--with-tcltkversion=#{@tcltk_version} --with-tcl-lib=#{@tcl_lib_path} --with-tk-lib=#{@tk_lib_path} --with-tcl-include=#{@tcl_include_path} --with-tk-include=#{@tk_include_path} --enable-pthread"
                when /darwin/
                  "--with-tcl-dir=#{@tcl_lib_path} --with-tk-dir=#{@tk_lib_path}"
                else
                  "--with-tcl-dir=#{@tcl_lib_path} --with-tk-dir=#{@tk_lib_path}"
                end
        cmd = "gem install tk -- #{flags}"
        cmd = "sudo #{cmd}" unless @os =~ /mswin|mingw/
        unless system(cmd)
          log "tk gem install failed."
          cleanup_and_exit(1)
        end
      end

      def test_tk
        log 'Testing Tk gem with Port1POS-branded test window'
        begin
          require 'tk'
          log "Tk version: #{Tk::TK_PATCHLEVEL}"
          root = TkRoot.new { title 'Port1POS Tk Test — Success!' }
          root['geometry'] = '420x160'
          TkLabel.new(root) { text "Tk is working for Port1POS!\nYou can now run: ruby lib/gui/tk_main.rb" }.pack(pady: 10)
          TkButton.new(root) { text 'Close'; command { exit } }.pack
          Tk.mainloop
          log 'Tk test passed!'
        rescue => e
          log "Tk test failed: #{e.message}"
          cleanup_and_exit(1)
        end
      end

      def cleanup_and_exit(code)
        log "Cleanup on failure (code #{code})"
        if @os =~ /linux/
          system "sudo apt-get remove -y tcl#{@supported_version}-dev tk#{@supported_version}-dev" rescue nil
        end
        exit code
      end

      def run
        log "=== Port1POS Tk Installer (integrated) ==="
        check_requirements
        detect_tcltk
        create_symlinks
        install_tk_gem
        test_tk
        log "=== Tk installation complete for Port1POS ==="
        log "You can now safely run the GUI: ruby lib/gui/tk_main.rb"
      end
    end
  end
end

# Direct run support
if __FILE__ == $0
  Port1POS::Setup::TkInstaller.new.run
end
