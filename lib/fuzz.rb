
class Dirfuzz

  def initialize(options, env)
    @options = options
    @dirs  = env[:dirs]
    @ofile = env[:ofile]
    @baseurl = env[:baseurl]
    @threads = env[:thread_queue]
  end

  def normalize_location_header(location)
    location = location.gsub(" ", "")
    location.split("/")
  end

  def parse_absolute_location(location)
    host = location[2]

    if location[3] == nil
      lpath = "/"
    else
      lpath = "/" + location[3]
    end

    [host, lpath]
  end

  def parse_relative_location(location)
    host = @baseurl

    if location[1] == nil
      lpath = @options[:path] + location[0]
    else
      lpath = "/" + location[1]
    end

    [host, lpath]
  end

  # The location header can come in two forms
  # an absolute URL or a relative one
  def get_host_and_path(location)
    split_location = normalize_location_header(location)

    if location.start_with? "http://"
      parse_absolute_location(split_location)
    else
      parse_relative_location(split_location)
    end
  end

  def redir_do(location, output)
    orig_loc   = location.sub("http://", "")
    host, path = get_host_and_path(location)

    # Follow redirect
    fredirect = Http.get(host, @ip, path, "")

    clear_line() unless @options[:multi]
    print_output(output[0] + "  [ -> " + orig_loc + " " + fredirect.code.to_s + "]", output[1])

    code = output[0].scan(/\d{3} \w+/).first
    return [output[1], "#{code}  [ -> #{orig_loc} #{fredirect.code} ]"]
  end

  def repeated_response(code)
    if host['dirs'].any? && code.name == host['dirs'].last[1]
      unless code.code == 200 && extra != host['dirs'].last[2]
        @repeated_count += 1
        ignore_repeated_response(code) if @repeated_count >= 6
      end
    else
      @repeated_count = 0
    end
  end

  def ignore_repeated_response(code)
    @options[:redir] = "" if @options[:redir].instance_of? Fixnum
    @options[:redir] << code.code.to_s
    puts "Too many #{code.code} reponses in a row, ignoring...\n\n" unless @options[:multi]
  end

  def get_output_data(get, code, path)
    if code.ok
      extra = "  - Len: " + get.len.to_s
      extra = "  - Dir. Index" if get.body.include?("Index of #{path}")
      extra = "  - Dir. Index" if get.len == nil and @options[:get] == false
    end

    extra = "" if extra == nil

    return extra
  end

  def start_crawler(html)
    level = @options[:links].to_i
    print_output("%blue", "\n[+] Links: ")
    print "Crawling..." if level == 1

    crawler = Crawler.new(@baseurl, html)
    crawler.run(level)

    clear_line()
    crawler.print_links @ofile

    print_output("%blue","\n[+] Dirs: ")
    puts
  end

  def check_redirect(get)
    ssl_redirect_msg = "Sorry couldn't retrieve links - Main page redirected to SSL site, try port 443."

    if (get.code == 301 || get.code == 302)
      location = get.headers['Location']

      if location.include? "https://"
        puts ssl_redirect_msg if @options[:links]
        @options[:links] = false
      elsif location.include? "http://"
        get = Http.open(location)
      else
        get = Http.open(@baseurl + location)
      end
    end

    return get
  end

  def print_generator(html)
    generator = false
    meta = html.xpath("//meta")
    meta.each { |m| generator = m[:content] if m[:name] == "generator" }

    if generator
      print_output("%green %yellow", "[%] Meta-Generator: ", "#{generator}\n\n")
    end
  end

  def get_title(html)
    title = html.xpath("//title")

    if title.any?
      title.first.text
    else
      "(No title)"
    end
  end

  def get_spaces(req)
    if req.length < 16
      " " * (16 - req.length)
    else
      " " * 16
    end
  end

  def process_results(path, code, extra, get, output)
    if (code.redirect?)    # Check if we got a redirect
      if @options[:redir] == 0
        # Follow redirect
        redir_do(get.headers['Location'], output)
      end
    elsif (code.found_something?)    # Check if we found something and print output
      return "" if code.ignore? @options[:redir]

      clear_line()
      print_output(output[0], output[1])

      # Save the results for processing later
      [path, code.name, extra]
    end
  end

  def initial_request
    @ip = Http.resolv(@baseurl) # Resolve name or just return the ip
    print_output("%green %yellow","[+] Starting fuzz for:", @baseurl)
    puts "[ multi-scan ] Starting for: #{@baseurl}" if @options[:multi]

    begin
      get = Http.get(@baseurl,@ip,@options[:path],@options[:headers])
    rescue Timeout::Error
      puts "[-] Connection timed out - the host isn't responding.\n\n"
      return
    rescue Errno::ECONNREFUSED
      puts "[-] Connection refused - the host or service is not available.\n\n"
      return
    end

    server = get.headers['Server']
    print_output("%green %yellow","[+] Server:","#{server}")

    get = check_redirect(get)
    html = Nokogiri::HTML.parse(get.body)

    print_generator(html)
    title = get_title(html)

    if @options[:info_mode]
      print_output("%green %yellow","[+] Title:","#{title}\n\n")
      return host
    end

    puts "" unless @options[:multi]

    # Crawl site if the user requested it
    if @options[:links]
      start_crawler(html)
    end

    [title, server]
  end

  def send_request(url)
    req = url.chomp
    # Add together the start path, the dir/file to test and the extension
    path = @options[:path] + req + @options[:ext]

    # HTTP request
    start_time = Time.now
    begin
      get = Http.get(@baseurl,@ip,path,@options[:headers])  if @options[:get] == true  # get request (default)
      get = Http.head(@baseurl,@ip,path,@options[:headers]) if @options[:get] == false # head request
    rescue Exception => e
      unless e.is_a? Timeout::Error
        #puts "Failed http request for host #{@baseurl} path #{path} with error #{e.class}"
      end
    end
    end_time = Time.now - start_time

    # Make sure we got a valid response
    return false unless get.body

    # Parse HTTP response code
    code = Code.new(get)

    # Remove trailing space and ending slash if there is one
    path.chomp!
    path.chop! if path =~ /\/$/

    # Prepare extra info, like response length.
    extra  = get_output_data(get, code, path)
    spaces = get_spaces(req)

    output = ["%yellow" + spaces + "  => " + code.name + extra, path]
    # Update progress
    @progress_bar.update

    process_results(path, code, extra, get, output)
  end

  def run
    beginning = Time.now

    host = {}
    host['url']  = @baseurl
    host['dirs'] = []

    host['title'], host['server'] = initial_request

    if $stdout.isatty && !@options[:multi]
      @progress_bar = Progress.new  # Setup our progress bar
    end

    if @options[:multi]
      @progress_bar = ProgressMulti.new(@baseurl)
    end

    threads  = @options[:threads].to_i
    thread_queue  = WorkQueue.new(threads, threads) # Setup thread queue

    @dirs.each do |url|  # Iterate over our dictionary of words for fuzzing
      thread_queue.enqueue_b(url) do |url|   # Start thread block
        results = send_request(url)
        host['dirs'] << results if results
      end
    end

    thread_queue.join  # wait for threads to end
    thread_queue.kill

    clear_line()
    time = "%0.1f" % [Time.now - beginning]
    print_output("\n\n%green\n\n","[+] Fuzzing done! It took a total of #{time} seconds.")

    host['found'] = host['dirs'].size
    host['time']  = time.to_f
    return host
  end
end
