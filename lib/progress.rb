
class Progress
  def initialize
    @bar = ProgressBar.new("Fuzzing", 100, out=$stdout)
    @total_progress = 0
    @next_tick = 0
    @tty = $stdout.isatty
  end

  def increase_progress
    @next_tick % 37 == 0
  end

  def update
    return unless @tty
    @next_tick += 1

    # Show a 1% graphical increase
    @bar.inc if increase_progress
  end
end

class ProgressMulti < Progress

  def initialize(url)
    @total_progress  = 0
    @next_tick = 0
    @baseurl = url
  end

  def update
    @next_tick += 1

    if increase_progress
      output_percent_update
    end
  end

  def output_percent_update
    @total_progress += 1

    if @total_progress % 10 == 0
      puts "[ update ] #{@baseurl} -> #{@total_progress}%"
    end
  end
end
