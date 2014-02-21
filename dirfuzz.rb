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

require 'lib/fuzz'
require 'lib/http'
require 'lib/progressbar'
require 'lib/util'
require 'lib/crawl'
require 'lib/report'

require 'rubygems'
require 'term/ansicolor'
require 'work_queue'
require 'optparse'
require 'json'

include Util

class String
  include Term::ANSIColor
end

@env = {}

banner = "DirFuzz 1.5 Dev by matugm\nUsage: #{$0} host[:port] [options]\n"

if ARGV[0] == nil
  puts banner + "Please use -h for help."
  exit()
else
  @env[:baseurl] = ARGV[0].sub("http://","")
  @env[:baseurl].chop! if @env[:baseurl][-1] == "/"
end

@options = {}
optparse = OptionParser.new do |opts|

opts.banner = banner

  @options[:host_list] = Array(@env[:baseurl])
  opts.on('-r', '--read file', 'Read hosts to scan from a file.') do |file|
    begin
      fd = File.open(file)
    rescue Errno::ENOENT
      abort "The host file you specified does not exist."
    end
    @options[:host_list] = fd.readlines
    fd.close
  end

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

  @options[:path] = "/"
  opts.on( '-p', '--path path', 'Start path (Default: /)' ) do |path|
    unless path.start_with? "/"
      puts "[-] The path must start with a /"
      exit -1
    end
    @options[:path] = path
    @options[:path] += "/"
  end

  @options[:ext] = "/"
  opts.on( '-e', '--ext extension', 'Fuzz for files with this extension, instead of dirs.' ) do |ext|
    if ext !~ /\..*/
      abort "Please specify the extension with a dot, for example -e .php"
    end
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

  @options[:threads] = 6
   opts.on( '-t', '--threads num_threads', 'Set the number of threads (Default: 6)' ) do |num_threads|
     @options[:threads] = num_threads
  end

  @options[:cookie] = nil
   opts.on( '-c', '--cookie "cookie"', 'Use a cookie.' ) do |cookie|
     @options[:cookie] = cookie
  end

  # @options[:info_mode] = false
  #   opts.on( '-m','', 'Info mode: Only get basic info, don\'t fuzz.') do
  #     @options[:info_mode] = true
  # end

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
  @options[:headers] = ["Cookie: #{@options[:cookie]}"]
else
  @options[:headers] = ""
end


if @options[:nocolors] or !$stdout.isatty
  @options[:nocolors] = 1
else
  @options[:nocolors] = 0
end

if @options[:file]
  @env[:ofile] = File.open(@options[:file],'w+')
end


@options[:get] = true

# End of option parsing

file = File.new('data/fdirs.txt','r')  # Load dictionary file
@env[:dirs] = file.readlines
file.close

trap("INT") do   # Capture Ctrl-C
  @options[:file] = nil
  print_output("%red","\n[-] Stoped by user request...")
  exit! 1
end


def fuzz_host(host, mutex = Mutex.new)
  data = []
  @env[:baseurl] = host.chomp.strip
  return if @env[:baseurl] == ""
  fuzzer = Dirfuzz.new(@options, @env)

  begin
    data << fuzzer.run
  rescue InvalidHttpResponse
    puts "Server responded with an invalid http packet, skipping..."
    return
  rescue DnsFail => e
    puts "[-] Couldn't resolve name: #{@env[:baseurl]}\n\n"
    return
  rescue Exception => e
    puts "[-] Error -> " + e.message
    puts e.backtrace
  end

  # Save data if we got sane results
  return if !data[0]

  dircount = data[0]["dirs"].size
  if dircount < 100
    mutex.synchronize {
      File.open("log.json", "a+") { |file| file.puts data.to_json }
    }
  end

end

total_host = @options[:host_list].size

summary = {}
summary['finished']   = 0
summary['date']       = Time.now
summary['host_count'] = total_host

if total_host > 1
  host_queque = WorkQueue.new(5, 5)
  @options[:multi] = true
  mutex = Mutex.new

  puts "Starting multi-scan [ #{total_host} host ]"
  puts

  @options[:host_list].each do |host|
    host_queque.enqueue_b(host, mutex) do |host, mutex|
      fuzz_host(host, mutex)
      total_host -= 1
      puts "[ multi-scan ] Scan finished for #{host.chomp} [ #{total_host} host left ]"
    end
  end

  host_queque.join

  time = "%0.1f" % [Time.now - summary['date']]
  puts "[ multi-scan ] finished after #{time} seconds"
else
  host    = @options[:host_list].first
  threads = @options[:threads].to_i
  @env[:thread_queue] = WorkQueue.new(threads,threads*2)

  fuzz_host(host) 
end


summary['finished'] = "%0.1f" % [summary['finished']]

if @options[:info_mode]
  report = Report.new(report_dir)
  File.open(report_dir + "/report.html","w") { |file| file.puts report.generate(data,summary) }

  puts
  puts "Report generated in #{report_dir}/report.html"
end
