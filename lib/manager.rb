class FuzzManager
  def initialize(options, env)
    @env = env
    @options    = options
    @total_host = options[:host_list].size
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

  def fuzz_multi
    host_queque = WorkQueue.new(5, 5)
    @options[:multi] = true
    mutex = Mutex.new

    puts "Starting multi-scan [ #{@total_host} host ]"
    puts

    start = Time.now
    @options[:host_list].each do |host|
      host_queque.enqueue_b(host, mutex) do |host, mutex|
        fuzz_host(host, mutex)
        @total_host -= 1
        puts "[ multi-scan ] Scan finished for #{host.chomp} [ #{@total_host} host left ]"
      end
    end

    host_queque.join

    time = "%0.1f" % [Time.now - start]
    puts "[ multi-scan ] finished after #{time} seconds"
  end

  def fuzz_single
    host    = @options[:host_list].first
    threads = @options[:threads].to_i
    @env[:thread_queue] = WorkQueue.new(threads,threads*2)

    fuzz_host(host)
  end
end
