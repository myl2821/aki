require 'spec_helper'
require 'rest-client'

RSpec.describe Aki::Server do
  before do
    app = proc { |env| [200, { 'Content-Type' => 'text/plain' }, ['Hello World']] }
    @thread = Thread.new {
      @server = Aki::Server.new app, 2333
      @server.run
    }
    sleep 0.1
  end

  it 'should work' do
    resp = RestClient.get 'http://localhost:2333'
    expect(resp.code).to eq 200
    expect(resp.body).to eq 'Hello World'
    expect(resp.headers[:content_type]).to eq 'text/plain'
    expect(resp.headers[:content_length]).to eq '11'
  end

  after do
    @server.stop
  end
end

RSpec.describe Aki::EMServer do
  before do
    app = proc { |env| [200, { 'Content-Type' => 'text/plain' }, ['Hello World']] }
    @thread = Thread.new do
      @server = Aki::EMServer.new 2333, app
      @server.run
    end
    sleep 0.1
  end

  it 'should work' do
    resp = RestClient.get 'http://localhost:2333'
    expect(resp.code).to eq 200
    expect(resp.body).to eq 'Hello World'
    expect(resp.headers[:content_type]).to eq 'text/plain'
    expect(resp.headers[:content_length]).to eq '11'
  end

  after do
    @server.stop
  end
end
