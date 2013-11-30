
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

    clear_line() unless @options[:multi]
    print_output(output[0] + "  [ -> " + orig_loc + " " + fredirect.code.to_s + "]",output[1])

    code = output[0].scan(/\d{3} \w+/).first
    return [output[1], "#{code}  [ -> #{orig_loc} #{fredirect.code.to_s} ]"]
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

    print_output("%green %yellow","[+] Server:","#{get.headers['Server']}")

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

    title = html.xpath("//title")

    if title.any?
      host['title'] = title.first.text
    else
      host['title'] = "(No title)"
    end

    if @options[:info_mode]
      print_output("%green %yellow","[+] Title:","#{host['title']}\n\n")
      return host
    end

    puts "" unless @options[:multi]

    # Crawl site if the user requested it
    if @options[:links]

      level = @options[:links].to_i
      print_output("%blue","\n[+] Links: ")
      print "Crawling..." if level == 1
      crawler = Crawler.new(@baseurl,html)
      crawler.run(level)
      clear_line()
      out = crawler.print_links @ofile

      print_output("%blue","\n[+] Dirs: ")
      puts
    end

    if $stdout.isatty  and !@options[:multi]
      pbar = ProgressBar.new("Fuzzing", 100, out=$stdout) # Setup our progress bar
    end

    pcount   = 0
    repeated = 0
    progress = 0

    threads  = @options[:threads].to_i
    @threads = WorkQueue.new(threads,threads * 2) # Setup thread queue

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

      # Update progress
      pcount += 1

      if pcount % 37 == 0 
        if @options[:multi]
          progress += 1
          if progress % 10 == 0
            puts "[ update ] #{@baseurl} -> #{progress}%"
          end

        elsif $stdout.isatty
          pbar.inc
        end
      end

      if (code.redirect?)    # Check if we got a redirect
        if @options[:redir] == 0
          host['dirs'] << redir_do(get.headers['Location'],output)
        end
      elsif (code.found_something?)    # Check if we found something and print output
        next if code.ignore? @options[:redir]
        clear_line()
        print_output(output[0],output[1])

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
          host['dirs'] << [path, code.name, extra]
      end
        repeated = 0 if code.code == 404  # Reset counter if dir not found.
    end  # end thread block
  end

    @threads.join  # wait for threads to end

    clear_line()
    time = "%0.1f" % [Time.now - beginning]
    print_output("\n\n%green\n\n","[+] Fuzzing done! It took a total of #{time} seconds.")

    host['found'] = host['dirs'].size
    host['time'] = time.to_f
    return host
    end
end
