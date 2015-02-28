
optparse = OptionParser.new do |opts|

opts.banner = "DirFuzz 1.6 by matugm\nUsage: #{$0} host[:port] [options]\n"

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
