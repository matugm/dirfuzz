
# Report generator for Dirfuzz using Ruby HTML templating library (ERB)

require "erb"

class Report
	def initialize(report_dir)

		@report_dir = report_dir

		file = File.open("data/report.css", "r") { |file| file.readlines }
		@css = ERB.new(file.join)

		file = File.open("data/summary.html", "r") { |file| file.readlines }
		@summ = ERB.new(file.join)

		file = File.open("data/report.html", "r") { |file| file.readlines }
		@data_bloc = ERB.new(file.join)

	end

	def generate(data,summary)
		report = ""
		report << @css.result
		report << @summ.result(binding)

		data.each do |host|
			report << @data_bloc.result(binding)
		end

		return report
	end
end

# rep = Report.new

# data = []

# host = {}

# host['server'] = "Apache 2.2"
# host['title'] = "test"
# host['found'] = 2

# summary = {}
# summary['date'] = Time.now
# summary['finished'] = "120 seconds"
# summary['host_count'] = 20

# (1..20).each do |t|
# 	host = host.clone
# 	host['url'] = "192.168.1." + t.to_s
# 	# p host['url']
# 	data << host
# end

# File.open("/tmp/report.html","w") { |file| file.puts rep.generate(data,summary) }
