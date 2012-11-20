#!/usr/bin/env ruby

# This is a custom http library for dirfuzz and other tools

require 'socket'
require 'openssl'
require 'timeout'
require 'zlib'
require 'stringio'
require 'resolv'

class Http
# Sets the method to GET and calls request
  def self.get (host,ip,path,headers)
    method = "get"
    request(host,ip,path,method,headers)
  end
# Simple method for a quick GET request
  def self.open (host)
    method = "get"
    host.sub!("http://",'')
    host, path = host.split("/",2)
    ip = resolv(host)
    path = "" if path == nil
    path = "/" + path
    request(host,ip,path,method)
  end

  def self.post (host,ip,path,headers,data)
    method = "post"
    request(host,ip,path,method,headers,data)
  end

  def self.head (host,ip,path,headers)
    method = "head"
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
      sleep (2)
    end
  end

# Resolves a name and returns the ip
  def self.resolv (host)
    begin
      timeout 10 do
        host = port_split(host)[0]
        ip = Resolv.getaddress(host)
        # nxredir(ip)
        return ip
      end
    rescue
      raise DnsFail
    end
  end

# Check if the url ends with a colon and splits it, so we can use
# the supplied port, otherwise sets the port to 80
  def self.port_split (host)
    host, port = host.split(/:/)
    port ||= 80
    return host,port
  end
# Build, send and handle the actual http request
# returns an object of the Respone class that you can query
# for the results of the request.
  def self.request (host,ip,path,method,headers = "",data = "")

    host,port = port_split(host)
    agentset = 0

    case method
      when "get"  then buff = "GET "
      when "post" then buff = "POST "
      else buff = "HEAD "
    end

    buff += "#{path} HTTP/1.1\r\n"
    buff += "Host: #{host}\r\n"
    buff += "Connection: close\r\n"
    buff += "Accept-Encoding: identity; q=1, gzip; q=0.5\r\n"  # Prefer no encoding over gzip...

    if headers != ""
      headers.each do |header|
        buff += "#{header}\r\n"
        if header =~ /User-Agent/i
          agentset = 1
        end
      end
    end

    buff += "User-Agent: Mozilla/5.0 (Windows; U; Windows NT 5.1; de; rv:1.9.2.3) Gecko/20100401 Firefox/4.0\r\n" if agentset == 0

    if method == "post"
      buff += "Content-Type: application/x-www-form-urlencoded\r\n"
      buff += "Content-Length: " + data.length.to_s + "\r\n"
      buff += "\r\n" + data
    else
      buff += "\r\n"
    end

    send_request(ip,port,buff)
  end

  def self.send_request (ip, port, buff)
    # TO DO: Add proxy support
    sc = timeout 5 do     # Throws an exception Timeout::Error if we can't connect in 5 seconds
      connection(ip, port)
    end
    sc.write(buff)
    sc.sync = false
    res = []
    while data = sc.read(1024 * 4)   # Read data from the socket
      res << data
    end
    # p "Data received. Len: #{res.join.size}"

    sc.close
    obj = Response.new(res.join)

    return obj   # Return a response object
  end

  def self.connection(ip,port)
    socket = TCPSocket.open(ip, port)
    if port == "443"
      context = OpenSSL::SSL::SSLContext.new
      ssl_client = OpenSSL::SSL::SSLSocket.new socket, context
      ssl_client.connect
      return ssl_client
    end
    return socket
  end

end

class DnsFail < StandardError
end

class InvalidHttpResponse < StandardError
end

class Response

  def initialize(res)
    @res = res
    @headers = Hash.new

    if res.empty?
      raise InvalidHttpResponse
    end

    split_data
    parse_headers
    set_size
    check_encoding
    set_code
  end

  def split_data
    b = res.split("\r\n\r\n",2)
    @res = res.split("\r")
    @raw_headers = b[0].split("\r")
    @raw_headers.delete_at(0)
    @body = b[1]

    if @body.nil? or @body.empty?
      raise InvalidHttpResponse
    end
  end

  def parse_headers
    for i in @raw_headers    # Parse headers into a hash
      temp = i.split(/:/, 2)
      temp[0] = temp[0].sub("\n","")
      @headers["#{temp[0]}"] = temp[1].lstrip
    end
  end

  def set_size
    if headers["Content-Length"]
      @len = headers["Content-Length"]
    else
      @len = @body.length
    end
  end

  def check_encoding
    if headers["Transfer-Encoding"] == "chunked"
      decode_chunked
    end

    if headers["Content-Encoding"] == "gzip" and @body.length > 0
      @body = Zlib::GzipReader.new(StringIO.new(@body)).read
      @len = @body.length
    end
   end

  def decode_chunked
    puntero = 0
    tmp_buffer = ""
    while (size = @body[puntero..@body.length].scan(/^[0-9a-f]+\r\n/)[0]) != "0\r\n"
      size_decimal = size.to_i(16)
      puntero += size.length
      tmp_buffer += @body[puntero..puntero+size_decimal-1]
      puntero += size_decimal+2
    end
    @body = tmp_buffer
    @len = @body.length
  end

  def set_code
    code = res[0].split(" ")
    @code = code[1].to_i
    name = res[0]
    @code_with_name = name[9,(name.length-9)]
  end

  attr_reader :code, :code_with_name, :body, :headers, :len, :res

end

