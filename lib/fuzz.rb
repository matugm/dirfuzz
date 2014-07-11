
class Dirfuzz

  def initialize(options,env)
    @options = options
    @dirs  = env[:dirs]
    @ofile = env[:ofile]
    @baseurl = env[:baseurl]
    @threads = env[:thread_queue]
  end

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
      host = @baseurl
      if location[1] == nil
        lpath = @options[:path] + location[0]
      else
        lpath = "/" + location[1]
      end
    end

    fredirect = Http.get(host,@ip,lpath,"")  # Send request to find out more about the redirect...

    clear_line() unless @options[:multi]
    print_output(output[0] + "  [ -> " + orig_loc + " " + fredirect.code.to_s + "]",output[1])

    code = output[0].scan(/\d{3} \w+/).first
    return [output[1], "#{code}  [ -> #{orig_loc} #{fredirect.code.to_s} ]"]
  end

  def repeated_response
    if host['dirs'].any? and code.name == host['dirs'].last[1]
      unless code.code == 200 and extra != host['dirs'].last[2]
        repeated += 1
        if repeated >= 6
          @options[:redir] = "" if @options[:redir].instance_of? Fixnum
          @options[:redir] << code.code.to_s
          puts "Too many #{code.code} reponses in a row, ignoring...\n\n" unless @options[:multi]
        end
      end
    else
      repeated = 0
    end
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
    print_output("%blue","\n[+] Links: ")
    print "Crawling..." if level == 1
    crawler = Crawler.new(@baseurl, html)
    crawler.run(level)
    clear_line()
    out = crawler.print_links @ofile

    print_output("%blue","\n[+] Dirs: ")
    puts
  end

  def check_redirect(get)
    if (get.code == 301 or get.code == 302)
      if get.headers['Location'].include? "https://"
        puts "Sorry couldn't retrieve links - Main page redirected to SSL site, you may want to try setting the port to 443." if @options[:links]
      elsif get.headers['Location'].include? "http://"
        get = Http.open(get.headers['Location'])
      else
        get = Http.open(@baseurl + get.headers['Location'])
      end
    end

    return get
  end

  def print_generator(html)
    generator = false
    meta = html.xpath("//meta")
    meta.each { |m| generator = m[:content] if m[:name] == "generator" }

    if generator
      print_output("%green %yellow","[%] Meta-Generator: ","#{generator}\n\n")
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
      spaces = " " * (16 - req.length)
    else
      spaces = " " * 16
    end
  end

  def run
    beginning = Time.now

    host = {}
    host['url'] = @baseurl
    host['dirs'] = []

    #puts "\e[H\e[2J" if $stdout.isatty  # Clear the screen

    @ip = Http.resolv(@baseurl) # Resolve name or just return the ip
    print_output("%green %yellow","[+] Starting fuzz for:",@baseurl)
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

    host['server'] = get.headers['Server']
    print_output("%green %yellow","[+] Server:","#{host['server']}")

    get = check_redirect(get)
    html = Nokogiri::HTML.parse(get.body)

    print_generator(html)
    host['title'] = get_title(html)

    if @options[:info_mode]
      print_output("%green %yellow","[+] Title:","#{host['title']}\n\n")
      return host
    end

    puts "" unless @options[:multi]

    # Crawl site if the user requested it
    if @options[:links]
      start_crawler(html)
    end

    if $stdout.isatty  and !@options[:multi]
      progress_bar = Progress.new  # Setup our progress bar
    end

    threads  = @options[:threads].to_i
    thread_queue  = WorkQueue.new(threads, threads) # Setup thread queue

    @dirs.each do |url|  # Iterate over our dictionary of words for fuzzing

      thread_queue.enqueue_b(url) do |url|   # Start thread block

      req = url.chomp
      path = @options[:path] + req + @options[:ext]   # Add together the start path, the dir/file to test and the extension

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
      next unless get.body

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
      progress_bar.update

      if (code.redirect?)    # Check if we got a redirect
        if @options[:redir] == 0
          # Follow redirect
          host['dirs'] << redir_do(get.headers['Location'], output)
        end
      elsif (code.found_something?)    # Check if we found something and print output
        next if code.ignore? @options[:redir]

        clear_line()
        print_output(output[0], output[1])

        # Save the results for processing later
        host['dirs'] << [path, code.name, extra]
      end

    end  # end thread block
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
