#!/usr/bin/env ruby

# DirFuzz - Directory discovery of web applications
# Copyright (C) 2011-2012 Jesus Castello Lupon
# email: matugm@gmail.com

#This tool is free software; you can redistribute it and/or
#modify it under the terms of the GNU Lesser General Public
#License as published by the Free Software Foundation; either
#version 2.1 of the License, or (at your option) any later version.

#DirFuzz is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#Lesser General Public License for more details.

#You should have received a copy of the GNU Lesser General Public
#License along with this tool; If not, see <http://www.gnu.org/licenses/>

$: << '.'

require 'lib/http'
require 'lib/progressbar'
require 'lib/util'
require 'lib/crawl'

require 'rubygems'
require 'term/ansicolor'
require 'work_queue'
require 'optparse'
require 'nokogiri'

include Util

class String
  include Term::ANSIColor
end

cr = "\r"
clear = "\e[0K"
reset = cr + clear
@reset = reset

banner = "DirFuzz 1.4 by matugm\nUsage: #{$0} host[:port] [options]\n"

if (ARGV[0] == nil or ARGV[0] !~ /.+\..+/) and ARGV[0] !~ /^localhost/ and ARGV[0] != "-h"
  puts banner + "Please use -h for help."
  exit()
else
  $baseurl = ARGV[0].sub("http://","")
  $baseurl.chop! if $baseurl[-1] == "/"
end

@options = {}
optparse = OptionParser.new do |opts|

opts.banner = banner

   @options[:redir] = 0
   opts.on( '-i', '--ignore [c:code]', 'Ignore redirects or a specific http code.' ) do |ignore|
    if ignore == nil    # We only get nil if the option is passed, but without an argument.
      @options[:redir] = 1
    else
      @options[:redir] = ignore
    end
  end

   @options[:nocolors] = false
   opts.on( '-u', '--uncolor', 'Disable colored output.' ) do
    @options[:nocolors] = true
  end

   @options[:path] = nil
   opts.on( '-p', '--path path', 'Start path (Default: /)' ) do |path|
    unless path.start_with? "/"
      puts "[-] The path must start with a /"
      exit -1
    end
    @options[:path] = path
  end

   @options[:ext] = nil
   opts.on( '-e', '--ext extension', 'Fuzz for files with this extension, instead of dirs.' ) do |ext|
    @options[:ext] = ext
  end

   @options[:file] = nil
   opts.on( '-o', '--out file', 'Write output to file.' ) do |file|
    @options[:file] = file
  end

   @options[:links] = nil
   opts.on( '-l level', '--links level',
   'With level 0 extract all links from frontpage,
    with level 1 perform a crawling of one level of depth to extract more links.' ) do |level|
    if not level.scan(/[01]/).empty?
      @options[:links] = level
    else
      puts "You must suply the number 0 or 1 with the links option."
      exit -1
    end
  end

   #@options[:get] = false
   #opts.on( '-g', '--get', 'Use GET method (Default: HEAD)' ) do
     #@options[:get] = true
  #end          # TODO: think new help text and flag to set head, get is default now

  @options[:threads] = 6
   opts.on( '-t', '--threads num_threads', 'Set the number of threads (Default: 6)' ) do |num_threads|
     @options[:threads] = num_threads
  end

  @options[:cookie] = nil
   opts.on( '-c', '--cookie "cookie"', 'Use a cookie.' ) do |cookie|
     @options[:cookie] = cookie
  end

  opts.on( '-h', '--help', 'Display this screen.' ) do
    puts opts
    exit
  end

end


begin
  optparse.parse!
rescue OptionParser::InvalidOption
  puts  $!.to_s + "\n" * 2
  puts optparse
  exit
end

if @options[:cookie]
  headers = ["Cookie: #{@options[:cookie]}"]
else
  headers = ""
end

unless @options[:path]
  @options[:path] = ""
end

@options[:path] += "/"

if @options[:nocolors] or !$stdout.isatty
  @options[:nocolors] = 1
else
  @options[:nocolors] = 0
end

if @options[:get]
  head = 0
else
  head = 1
end

if @options[:file]
  @ofile = File.open(@options[:file],'w+')
  ofile = @ofile
end

if @options[:ext]
  ext = @options[:ext]
  if ext !~ /\..*/
    puts "Please specify the extension with a dot, for example -e .php"
    exit
  end
else
  ext = "/"
end

@options[:get] = true

# End of option parsing

file = File.new('data/fdirs.txt','r')  # Load dictionary file
lines = file.readlines
file.close

threads = @options[:threads].to_i
threads = WorkQueue.new(threads,threads*2) # Setup thread queue

trap("INT") do   # Capture Ctrl-C
  print_output("%red","\n[-] Stoped by user request...")
  exit 1
  end

beginning = Time.now

puts "\e[H\e[2J" if $stdout.isatty

$ip = Http.resolv($baseurl) # Resolve name or just return the ip


print_output("%green %yellow","[+] Starting fuzz for:",$baseurl)

begin
  get = Http.get($baseurl,$ip,@options[:path],headers)
rescue Timeout::Error
  puts "[-] Connection timed out - the host isn't responding.\n\n"
  exit
rescue Errno::ECONNREFUSED
  puts "[-] Connection refused - the host or service is not available.\n\n"
  exit
rescue Exception => e
  puts "[Error] " + e.message
  puts
  exit
end

print_output("%green %yellow","[+] Server:","#{get.headers['Server']}\n\n")


if (get.code == 301 or get.code == 302)
  if get.headers['Location'].include? "https://"
    puts "Sorry couldn't retrieve links - Main page redirected to SSL site, you may want to try setting the port to 443." if @options[:links]
  elsif get.headers['Location'].include? "http://"
    get = Http.open(get.headers['Location'])
  else
    get = Http.open($baseurl + get.headers['Location'])
  end
end

html = Nokogiri::HTML.parse(get.body)

generator = nil
meta = html.xpath("//meta")
meta.each { |m| generator = m[:content] if m[:name] == "generator" }

if generator
  print_output("%green %yellow","[%] Meta-Generator: ","#{generator}\n\n")
end

if @options[:links]

  level = @options[:links].to_i
  puts "\n[+] Links: "
  print "Crawling..." if level == 1
  crawler = Crawler.new($baseurl,html)
  crawler.run(level)
  puts "#{reset}"
  crawler.print_links @ofile

  puts "\n[+] Dirs: "
  puts
end

pbar = ProgressBar.new("Fuzzing", 100, out=$stdout) if $stdout.isatty # Setup our progress bar
pcount = 0

def redir_do(location,output)

    if location.start_with? "http://"
      relative = false
    else
      relative = true
    end

    orig_loc = location.sub("http://","")
    location = location.gsub(" ","")
    location = location.split("/")
    host = location[2]

    if location[3] == nil
      lpath = "/"
    else
      lpath = "/" + location[3]
    end

    if relative
      host = $baseurl
      if location[1] == nil
        lpath = @options[:path] + location[0]
      else
        lpath = "/" + location[1]
      end
    end

    fredirect = Http.get(host,$ip,lpath,"")  # Send request to find out more about the redirect...

    print "#{@reset}" if $stdout.isatty
    print_output(output[0] + "  [ -> " + orig_loc + " " + fredirect.code.to_s + "]",output[1])

end


for url in lines do   # For each line in our dictionary...

  threads.enqueue_b(url) do |url|   # Start thread block
  req = url.chomp
  path = @options[:path] + req + ext      # Add together the start path, the dir/file to test and the extension

  get = Http.head($baseurl,$ip,path,headers) if @options[:get] == false # Send a head request
  get = Http.get($baseurl,$ip,path,headers) if @options[:get] == true  # Send a get request (default)
  code = Code.new(get)

  path.chomp!
  path.chop! if path =~ /\/$/ # Remove ending slash if there is one

  extra = "  - Len: " + get.len.to_s if code.ok
  extra = "  - Dir. Index" if get.body.include?("Index of #{path}") and code.ok
  extra = "  - Dir. Index" if get.len == nil and code.ok and @options[:get] == false
  extra = "" if extra == nil

  output = ["%yellow" + " " * (16 - req.length) + "  => " + code.name + extra, path]

  pcount += 1
  pbar.inc if pcount % 37 == 0 if $stdout.isatty

  if (code.redirect?)    # Check if we got a redirect
    if @options[:redir] == 0
      redir_do(get.headers['Location'],output)
    end
  elsif (code.found_something?)    # Check if we found something and print output
    next if code.ignore? @options[:redir]
    print "#{reset}" if $stdout.isatty
    print_output(output[0],output[1])
  end

end  # end thread block


end

threads.join  # wait for threads to end

print_output("%green","\n\n[+] Fuzzing done! It took a total of %0.1f seconds.\n" % [Time.now - beginning])

