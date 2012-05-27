
class Dirfuzz

  def initialize(options,env)
    @options = options
    @dirs = env[:dirs]
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

      clear_line()
      print_output(output[0] + "  [ -> " + orig_loc + " " + fredirect.code.to_s + "]",output[1])

    end

  def run
    beginning = Time.now

    puts "\e[H\e[2J" if $stdout.isatty  # Clear the screen

    @ip = Http.resolv(@baseurl) # Resolve name or just return the ip
    print_output("%green %yellow","[+] Starting fuzz for:",@baseurl)

    begin
      get = Http.get(@baseurl,@ip,@options[:path],@options[:headers])
    rescue Timeout::Error
      puts "[-] Connection timed out - the host isn't responding.\n\n"
      exit
    rescue Errno::ECONNREFUSED
      puts "[-] Connection refused - the host or service is not available.\n\n"
      exit
    rescue Exception => e
      puts "[Error] " + e.message
      puts e.backtrace
      exit
    end

    print_output("%green %yellow","[+] Server:","#{get.headers['Server']}\n\n")


    if (get.code == 301 or get.code == 302)
      if get.headers['Location'].include? "https://"
        puts "Sorry couldn't retrieve links - Main page redirected to SSL site, you may want to try setting the port to 443." if @options[:links]
      elsif get.headers['Location'].include? "http://"
        get = Http.open(get.headers['Location'])
      else
        get = Http.open(@baseurl + get.headers['Location'])
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
      print_output("%blue","\n[+] Links: ")
      print "Crawling..." if level == 1
      crawler = Crawler.new(@baseurl,html)
      crawler.run(level)
      clear_line()
      crawler.print_links @ofile

      print_output("%blue","\n[+] Dirs: ")
      puts
    end

    pbar = ProgressBar.new("Fuzzing", 100, out=$stdout) if $stdout.isatty # Setup our progress bar
    pcount = 0


    @dirs.each do |url|  # Iterate over our dictionary of words for fuzzing

      @threads.enqueue_b(url) do |url|   # Start thread block

      req = url.chomp
      path = @options[:path] + req + @options[:ext]      # Add together the start path, the dir/file to test and the extension
      get = Http.get(@baseurl,@ip,path,@options[:headers])  if @options[:get] == true  # Send a get request (default)
      get = Http.head(@baseurl,@ip,path,@options[:headers]) if @options[:get] == false # Send a head request
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
        clear_line()
        print_output(output[0],output[1])
      end
    end  # end thread block
  end

    @threads.join  # wait for threads to end

    clear_line()
    print_output("\n\n%green","[+] Fuzzing done! It took a total of %0.1f seconds.\n" % [Time.now - beginning])
    end
end
