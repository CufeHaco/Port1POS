# micro_ipc.rb - CRuby/JRuby Micro IPC with Bytecode/Byte tracking, Windows Named Pipe fallback, Error AST feedback
# Port1POS core IPC layer following Cufe style:
#   Build compact state (arrays, StringIO buffers, counters) →
#   Match transport (socket vs named pipe patterns) →
#   Verify connection/gates →
#   Execute fast path or graceful fallback with byte-level tracking
#
# Simple reliable protocol: 4-byte big-endian length prefix + payload
# Byte tracking on every send/receive for auditability and debugging

require 'socket'
require 'stringio'
require 'thread'  # for future thread-local if expanded

module Port1POS
  class MicroIPC
    DEFAULT_HOST = '127.0.0.1'
    DEFAULT_PORT = 18765  # Port1POS IPC port
    NAMED_PIPE_PATH = '\\\\.\\pipe\\port1pos_ipc'  # Windows named pipe (stub for JRuby Java interop)

    attr_reader :bytes_sent, :bytes_received, :transport_type, :connected

    def initialize(options = {})
      @options = options
      @state = build_state(options)
      @transport = nil
      @connected = false
      @bytes_sent = 0
      @bytes_received = 0
      @lock = Mutex.new  # basic thread safety for counters

      setup_transport
    end

    # High-level API
    def send_message(data)
      return false unless @connected

      payload = data.to_s
      length = [payload.bytesize].pack('N')  # 4-byte big-endian length

      buffer = StringIO.new
      buffer.write(length)
      buffer.write(payload)
      buffer.rewind

      execute_send(buffer)
    end

    def receive_message(timeout: nil)
      return nil unless @connected

      # Read length prefix with optional timeout (simple for now)
      len_data = read_exactly(4, timeout: timeout)
      return nil if len_data.nil? || len_data.bytesize < 4

      length = len_data.unpack1('N')
      return nil if length.nil? || length <= 0 || length > 1_000_000  # sanity gate

      payload = read_exactly(length, timeout: timeout)
      return nil if payload.nil?

      # Simple error AST feedback hook (expand later)
      if payload.start_with?('ERR:')
        code = parse_error_code(payload)
        feed_to_ast(code, payload)
        return { error: true, code: code, raw: payload }
      end

      payload
    end

    def close
      return unless @transport

      begin
        @transport.close if @transport.respond_to?(:close)
      rescue => e
        warn "[MicroIPC] Close warning: #{e.message}"
      end
      @connected = false
      @transport = nil
      puts "[MicroIPC] Connection closed. Total bytes: sent=#{@bytes_sent}, recv=#{@bytes_received}"
    end

    private

    # BUILD phase: compact state representation
    def build_state(options)
      runtime = match_runtime
      {
        runtime: runtime,
        host: options[:host] || DEFAULT_HOST,
        port: options[:port] || DEFAULT_PORT,
        pipe_path: options[:pipe_path] || NAMED_PIPE_PATH,
        use_named_pipe: options.fetch(:use_named_pipe, runtime[:windows] && !runtime[:jruby]), # prefer native on Windows CRuby
        errors: [],
        byte_counters: { sent: 0, received: 0 }
      }
    end

    # MATCH phase: fast runtime + transport classification
    def match_runtime
      is_jruby = defined?(JRUBY_VERSION)
      os = RbConfig::CONFIG['host_os']
      {
        jruby: is_jruby,
        windows: !!(os =~ /mswin|mingw|cygwin/),
        linux: !!(os =~ /linux|darwin/),
        os: os,
        ruby_version: RUBY_VERSION
      }
    end

    # Setup with verify + execute pattern
    def setup_transport
      state = @state
      runtime = state[:runtime]

      if runtime[:jruby] && state[:use_named_pipe]
        # JRuby path: Java named pipe / channels (JEP-380 friendly later)
        connect_named_pipe_jruby(state)
      elsif runtime[:windows]
        # Windows fallback (named pipe via external or TCP for now)
        connect_tcp(state)  # reliable cross-platform fallback
      else
        # Unix domain socket fast path (Linux/mac) or TCP
        begin
          connect_unix_socket(state)
        rescue
          connect_tcp(state)
        end
      end
    end

    def connect_unix_socket(state)
      socket_path = state[:pipe_path]  # reuse field or make separate
      # For simplicity in early version we use TCP even on Unix for reliability
      # (Unix domain can be added easily later)
      connect_tcp(state)
    end

    def connect_tcp(state)
      host = state[:host]
      port = state[:port]

      begin
        @transport = TCPSocket.new(host, port)
        @transport_type = :tcp
        @connected = true
        puts "[MicroIPC] Connected via TCP #{host}:#{port}"
      rescue Errno::ECONNREFUSED, SocketError => e
        @state[:errors] << "TCP connect failed: #{e.message}"
        @connected = false
        puts "[MicroIPC] TCP connection failed (#{e.message}). Server may not be listening yet."
      end
    end

    def connect_named_pipe_jruby(state)
      # Placeholder for JRuby + Java interop (JEP-380 channels or named pipe)
      # In real JRuby we would do:
      #   require 'java'
      #   pipe = java.io.RandomAccessFile.new(state[:pipe_path], "rw")
      # For now: graceful fallback to TCP with note
      puts "[MicroIPC] JRuby named pipe path selected — falling back to TCP for current dev (implement Java channel here later)"
      connect_tcp(state)
    end

    # VERIFY + EXECUTE for send with byte tracking
    def execute_send(buffer)
      return false unless @transport && @connected

      data = buffer.read
      byte_count = data.bytesize

      begin
        @transport.write(data)
        @transport.flush if @transport.respond_to?(:flush)

        @lock.synchronize do
          @bytes_sent += byte_count
          @state[:byte_counters][:sent] += byte_count
        end

        true
      rescue => e
        @state[:errors] << "Send error: #{e.message}"
        @connected = false
        false
      end
    end

    def read_exactly(nbytes, timeout: nil)
      return nil unless @transport && @connected

      buffer = StringIO.new
      remaining = nbytes

      begin
        while remaining > 0
          chunk = @transport.readpartial(remaining)
          buffer.write(chunk)
          remaining -= chunk.bytesize
        end

        data = buffer.string

        @lock.synchronize do
          @bytes_received += data.bytesize
          @state[:byte_counters][:received] += data.bytesize
        end

        data
      rescue EOFError, Errno::ECONNRESET => e
        @state[:errors] << "Read EOF/reset: #{e.message}"
        @connected = false
        nil
      rescue => e
        @state[:errors] << "Read error: #{e.message}"
        nil
      end
    end

    # Simple error code parser + AST feedback stub (expand with real AST later)
    def parse_error_code(payload)
      # Example: "ERR:042:Invalid tender" → code 42
      match = payload.match(/ERR:(\d+)/)
      match ? match[1].to_i : 999
    end

    def feed_to_ast(error_code, raw_payload)
      # Future: feed into Kestówv / error AST for sovereign logging + pattern matching
      # For now: structured log + hook point
      puts "[MicroIPC][ErrorAST] code=#{error_code} raw=#{raw_payload.inspect}"
      # Could push to a shared error ring buffer or thread-local state here
    end
  end
end

# Quick smoke test when run directly
if __FILE__ == $0
  puts "=== MicroIPC smoke test ==="
  ipc = Port1POS::MicroIPC.new
  puts "Connected: #{ipc.connected}"
  puts "Transport: #{ipc.transport_type || 'none'}"
  puts "Bytes counters: sent=#{ipc.bytes_sent}, recv=#{ipc.bytes_received}"

  if ipc.connected
    ipc.send_message("HELLO from Port1POS MicroIPC")
    response = ipc.receive_message(timeout: 1)
    puts "Response: #{response.inspect}"
  else
    puts "Note: No server listening — this is expected in early dev. Start a test server or ignore."
  end

  ipc.close
  puts "=== Smoke test complete ==="
end
