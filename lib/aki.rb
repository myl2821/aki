# encoding: BINARY

require 'socket'
require 'stringio'
require 'thread/pool'
require 'http/parser'
require 'eventmachine'
require 'logger'
require 'rack'
require 'uri'

LOGGER = Logger.new STDOUT

module Aki
  VERSION = '0.1.0'

  class Connection
    def initialize socket, app
      @socket = socket
      @app = app
      @parser = Http::Parser.new self
    end

    def on_message_begin
      @headers = nil
      @body = ''
    end

    def << data
      @parser << data
    end

    def on_message_complete
      env = {}

      @headers.each do |k, v|
        k = "HTTP_" + k.upcase.gsub('-', '_')
        env[k] = v
      end

      url = @parser.request_url
      request_path, query_string = url.split '?', 2
      env["SERVER_NAME"] = 'localhost'
      env["PATH_INFO"] = request_path
      env["REQUEST_METHOD"] = @parser.http_method
      env["QUERY_STRING"] = query_string || ""
      env["SERVER_PORT"] = '3000'
      env["rack.version"] = Rack::VERSION
      env["rack.input"] = StringIO.new @body
      env["rack.errors"] = StringIO.new
      env["rack.logger"] = LOGGER
      env["rack.run_once"] = false
      env["rack.hijack?"] = false
      env["rack.multithread"] = false
      env["rack.multiprocess"] = false
      env["rack.url_scheme"] = "http"

      process env
    end

    def on_headers_complete headers
      @headers = headers
    end

    def on_body chunk
      @body << chunk
    end

    def process env
      status, headers, body = @app.call env

      # TODO: support chunked mode

      @socket.write "HTTP/1.1 #{status}\r\n"
      headers.each do |k, v|
        @socket.write "#{k}: #{v}\r\n"
      end
      @socket.write "\r\n"

      body.each { |chunk| @socket.write chunk }
      body.close if body.respond_to? :close
    end
  end

  class Server
    def initialize app, port
      @app = Rack::ContentLength.new app
      @server = TCPServer.new port
      @prefork = false
    end

    def prefork workers
      @prefork = true
      @workers = workers
    end

    def run
      if @prefork
        @workers.times do
          fork do
            puts "Forked #{Process.pid}"
            start
          end
        end
        Process.waitall
      else
        start
      end
    end

    def stop
      @server.close
    end

    def start
      @pool = Thread.pool 20

      loop do
        begin
          socket = @server.accept
        rescue IOError => ex
          break if ex.message =~ /stream closed in another thread/
          raise ex
        end

        # TODO: support chunked mode

        # Thread.new {
        @pool.process {
          connection = Connection.new socket, @app
          begin
            until socket.closed? || socket.eof?
              data = socket.readpartial 4096
              connection << data
            end
          rescue Errno::ECONNRESET
          rescue Errno::EPIPE
          end
        }
      end
    end
  end

  class EMServer
    def initialize port, app
      @port = port
      @app = app
    end

    def print_banner
      puts "Aki starting..."
    end

    def run
      print_banner
      EM.run do
        EM.threadpool_size = 16
        EM.start_server "0.0.0.0", @port, EMConnection, @app
        puts "Listening on tcp://0.0.0.0:#{@port}"
      end
    end

    def stop
      EM.stop
    end
  end

  class EMConnection < EM::Connection
    def initialize app
      @app = Rack::ContentLength.new app
    end

    # EM hooks
    def post_init
      @parser = Http::Parser.new self
    end

    def receive_data data
      @parser << data
    end

    def unbind
    end

    def on_message_begin
      @headers = nil
      @body = ''
    end

    # HTTP parser hooks
    def on_message_complete
      env = {}

      @headers.each do |k, v|
        k = "HTTP_" + k.upcase.gsub('-', '_')
        env[k] = v
      end

      url = @parser.request_url
      request_path, query_string = url.split '?', 2
      env["SERVER_NAME"] = 'localhost'
      env["PATH_INFO"] = request_path
      env["REQUEST_METHOD"] = @parser.http_method
      env["QUERY_STRING"] = query_string || ""
      env["SERVER_PORT"] = '3000'
      env["rack.version"] = Rack::VERSION
      env["rack.input"] = StringIO.new @body
      env["rack.errors"] = StringIO.new
      env["rack.logger"] = LOGGER
      env["rack.run_once"] = false
      env["rack.hijack?"] = false
      env["rack.multithread"] = false
      env["rack.multiprocess"] = false
      env["rack.url_scheme"] = "http"


      # Let the thread pool handle request
      EM.defer(->() { process env })
      # process env
    end

    def on_headers_complete headers
      @headers = headers
    end

    def on_body chunk
      @body << chunk
    end

    def process env
      status, headers, body = @app.call env

      send_data "HTTP/1.1 #{status}\r\n"

      headers.each do |k, v|
        send_data "#{k}: #{v}\r\n"
      end

      send_data "\r\n"

      body.each { |chunk| send_data chunk }
      body.close if body.respond_to? :close


      # @socket.close
    end
  end
end

if __FILE__ == $0
  app, _ = Rack::Builder.parse_file 'config.ru'

  #server = Tube.new app, 3000
  #server.prefork 4
  #server.run

  server = Aki::EMServer.new 3000, app
  server.run
end
