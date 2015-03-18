#!/usr/bin/env ruby

# DirFuzz - Directory discovery of web applications
# Copyright (C) 2011-2015 Jesus Castello (matugm)
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
require 'lib/progress'
require 'lib/progressbar'
require 'lib/util'
require 'lib/crawl'
require 'lib/manager'
require 'lib/report'

require 'term/ansicolor'
require 'work_queue'
require 'optparse'
require 'json'

include Util

class String
  include Term::ANSIColor
end

@env = {}
@options = {}

@options[:get] = true

banner = "DirFuzz 1.6 by matugm\nUsage: #{$PROGRAM_NAME} host[:port] [options]\n"

if ARGV[0] == nil
  puts banner + "Please use -h for help."
  exit
else
  @env[:baseurl] = get_base_url(ARGV[0])
end

require 'lib/options'

### End of option parsing

file = File.new('data/fdirs.txt', 'r')  # Load dictionary file
@env[:dirs] = file.readlines
file.close

trap("INT") do   # Capture Ctrl-C
  @options[:file] = nil
  print_output("%red", "\n[-] Stoped by user request...")
  exit! 1
end

total_host = @options[:host_list].size

summary = {}
summary['finished']   = 0
summary['date']       = Time.now
summary['host_count'] = total_host

manager = FuzzManager.new @options, @env

if total_host > 1
  manager.fuzz_multi
else
  manager.fuzz_single
end

summary['finished'] = "%0.1f" % [summary['finished']]

if @options[:info_mode]
  report = Report.new(report_dir)
  File.open(report_dir + "/report.html","w") { |file| file.puts report.generate(data, summary) }

  puts
  puts "Report generated in #{report_dir}/report.html"
end
