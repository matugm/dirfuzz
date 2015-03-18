#!/usr/bin/env ruby

# This is a custom http library for dirfuzz and other tools

require 'socket'
require 'openssl'
require 'timeout'
require 'zlib'
require 'stringio'
require 'resolv'

class Request
  attr_reader :buff, :agentset

  def initialize(host, method, path)
    @buff = ""
    @agentset = 0

    case method
    when "get"  then @buff = "GET "
    when "post" then @buff = "POST "
    else @buff = "HEAD "
    end

    @buff += "#{path} HTTP/1.1\r\n"
    @buff += "Host: #{host}\r\n"
    @buff += "Connection: close\r\n"
    @buff += "Accept-Encoding: gzip;q=1.0, deflate;q=0.6, identity;q=0.3\r\n"
  end

  def user_agent=(agent)
    @buff += agent unless @agentset
  end

  def build_headers(headers)
    headers.each do |header|
      @buff += "#{header}\r\n"
      @agentset = 1 if header =~ /User-Agent/i
    end
  end
end

class Http
  # Sets the method to GET and calls request
  def self.get(host,ip,path,headers)
    method = 'get'
    request(host,ip,path,method,headers)
  end

  # Parse URL for path and host name, then make a GET request
  def self.open(host)
    method = 'get'
    host.sub!('http://', '')
    host, path = host.split("/", 2)
    path = '' if path == nil
    path = '/' + path

    ip = resolv(host)
    request(host,ip,path,method)
  end

  def self.post (host,ip,path,headers,data)
    method = 'post'
    request(host,ip,path,method,headers,data)
  end

  def self.head (host,ip,path,_)
    method = 'head'
    request(host,ip,path,method)
  end

  def self.nxredir (ip)
    begin
      nxredir = Socket.getaddrinfo("www.random-stuff-" + rand(5000).to_s + ".com", nil)
      nxredir = nxredir[0][3]
    rescue
    end

    if (ip == nxredir)
      puts "\n[-] Warning: Inexistent domain, you are most likely being redirected by your dns server."
      sleep(2)
    end
  end

  # Resolves a name and returns the ip address
  def self.resolv (host)
    retry_count = 0

    begin
      retry_count += 1

      timeout 3 do
        host = port_split(host)[0]
        ip   = Resolv.getaddress(host)
        return ip
      end
    rescue Resolv::ResolvError
      raise DnsFail
    rescue Timeout::Error
      retry if retry_count < 3
      raise DnsTimeout
    end
  end

# Check if the url ends with a colon and splits it, so we can use
# the supplied port, otherwise sets the port to 80
  def self.port_split(host)
    host, port = host.split(/:/)
    port ||= 80
    return host,port
  end
# Build, send and handle the actual http request
# returns an object of the Respone class that you can query
# for the results of the request.
  def self.request (host,ip,path,method,headers = "",data = "")

    host, port = port_split(host)
    req = Request.new(host, method, path)

    unless headers.empty?
      req.build_headers(headers)
    end

    req.user_agent = "Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:25.0) Gecko/20100101 Firefox/25.0\r\n"
    buff = req.buff

    if method == "post"
      buff += "Content-Type: application/x-www-form-urlencoded\r\n"
      buff += "Content-Length: #{data.length}\r\n"
      buff += "\r\n" + data
    else
      buff += "\r\n"
    end

    send_request(ip, port, buff)
  end

  def self.send_request(ip, port, buff)
    # TO DO: Add proxy support
    timeout 10 do     # Throws an exception Timeout::Error if we can't connect in 5 seconds
      sc = connection(ip, port)

      sc.write(buff)
      sc.sync  = false
      raw_data = []

      while data = sc.read(1024 * 4)   # Read data from the socket
        raw_data << data
      end

      sc.close
      Response.new(raw_data.join)
    end
  end

  def self.connection(ip,port)
    socket = TCPSocket.open(ip, port)
    if port == '443'
      context    = OpenSSL::SSL::SSLContext.new
      ssl_client = OpenSSL::SSL::SSLSocket.new socket, context
      ssl_client.connect
      return ssl_client
    end
    return socket
  end

end

class DnsFail < StandardError
end

class DnsTimeout < StandardError
end

class InvalidHttpResponse < StandardError
end


class Response

  def initialize(raw_data)
    if raw_data.empty?
      raise InvalidHttpResponse
    end

    raw_headers, body      = parse_data(raw_data)
    @code, @code_with_name = parse_code(raw_data)
    @headers = parse_headers(raw_headers)
    @body    = decode_data(body)
    @len     = get_size(body)
  end

  def parse_data(raw_data)
    raw_headers, body = raw_data.split("\r\n\r\n",2)

    raw_headers = raw_headers.split("\r")
    raw_headers.delete_at(0)

    if body.nil? || !raw_data.start_with?('HTTP')
      raise InvalidHttpResponse
    end

    return raw_headers, body
  end

  def parse_headers(raw_headers)
    headers = Hash.new

    raw_headers.each do |header|    # Parse headers into a hash
      temp  = header.split(/:/, 2)
      name  = temp[0].sub("\n", "").capitalize
      headers[name] = temp[1].lstrip
    end

    return headers
  end

  def get_size(body)
    headers.fetch("Content-Length", body.length)
  end

  def decode_data(body)
    if headers["Transfer-Encoding"] == "chunked"
      data = decode_chunked(body)
      data = body if data.empty?
    else
      data = body
    end

    # Stop if we don't have any data
    return if data.length <= 0

    if headers["Content-Encoding"] == "deflate"
      data = Zlib::Inflate.inflate(data)
    end

    if headers["Content-Encoding"] == "gzip"
      data = Zlib::GzipReader.new(StringIO.new(data)).read
    end

    return data || ""
  end

  def decode_chunked(body)
    @len = body.length
    body.split(/^[0-9a-fA-F]+\r\n/).join.split(/\r\n/).join
  end

  def parse_code(raw_data)
    raw_data = raw_data.split("\r")
    code = raw_data[0].split(" ")
    code = code[1].to_i
    name = raw_data[0]
    code_with_name = name[9,(name.length-9)]

    return code, code_with_name
  end

  attr_reader :code, :code_with_name, :body, :headers, :len

end
