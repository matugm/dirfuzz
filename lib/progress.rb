
class Progress
  def initialize()
    @bar = ProgressBar.new("Fuzzing", 100, out=$stdout)
    @total_progress = 0
    @next_tick = 0
  end

  def output_percent_update
    @total_progress += 1
    if @total_progress % 10 == 0
      puts "[ update ] #{@baseurl} -> #{progress}%"
    end
  end

  def update
    @next_tick += 1

    if @next_tick % 37 == 0 && $stdout.isatty
      # Show a 1% graphical increase
      @bar.inc
    end
  end
end
