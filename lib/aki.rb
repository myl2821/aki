# encoding: BINARY

require 'aki/version'
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
  module ConnectionMixin
    def process env
      status, headers, body = @app.call env

      send_data "HTTP/1.1 #{status}\r\n"

      chunked = false
      if headers['Content-Length'].nil?
        chunked = true
        headers['Transfer-Encoding'] = 'chunked'
      end

      headers.each do |k, v|
        send_data "#{k}: #{v}\r\n"
      end
      send_data "\r\n"

      body.each do |chunk|
        if chunked
          chunk_size = chunk.bytesize.to_s 16
          send_data "#{chunk_size}\r\n"
          send_data chunk
          send_data "\r\n"
        else
          send_data chunk
        end
      end

      if chunked
        send_data "0\r\n\r\n"
      end

      body.close if body.respond_to? :close
    end

    def receive_data data
      @parser << data
    end

    # HTTP parser hooks
    def on_message_begin
      @headers = nil
      @body = ''
    end

    def on_message_complete
      env = {}

      @headers.each do |k, v|
        k = "HTTP_" + k.upcase.gsub('-', '_')
        env[k] = v
      end

      url = @parser.request_url
      request_path, query_string = url.split '?', 2

      unless @headers['Host'].nil?
        server_name, port = @headers['Host'].split(':')
      end
      server_name ||= 'localhost'
      port ||= '80'

      env["SERVER_NAME"] = server_name
      env["SCRIPT_NAME"] = ''
      env["PATH_INFO"] = request_path
      env["REQUEST_METHOD"] = @parser.http_method
      env["QUERY_STRING"] = query_string || ""
      env["SERVER_PORT"] = port
      env["rack.version"] = Rack::VERSION
      env["rack.input"] = StringIO.new @body
      env["rack.errors"] = StringIO.new
      env["rack.logger"] = LOGGER
      env["rack.run_once"] = false
      env["rack.hijack?"] = false
      env["rack.multithread"] = false
      env["rack.multiprocess"] = false
      env["rack.url_scheme"] = "http"

      handle_env env
    end

    def on_headers_complete headers
      @headers = headers
    end

    def on_body chunk
      @body << chunk
    end
  end

  class Connection
    include ConnectionMixin
    def initialize socket, app
      @socket = socket
      @app = app
      @parser = Http::Parser.new self
    end

    def handle_env env
      process env
    end

    def send_data data
      @socket.write data
    end
  end

  class Server
    def initialize app, port
      @app = app
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
              connection.receive_data data
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
    include ConnectionMixin
    def initialize app
      @app = app
      @parser = Http::Parser.new self
    end

    def handle_env env
      EM.defer(->() { process env })
    end
  end
end

if __FILE__ == $0
  app, _ = Rack::Builder.parse_file 'config.ru'

  #server = Tube.new app, 3000
  #server.prefork 4
  #server.run

  server = Aki::EMServer.new app, 3000
  server.run
end
