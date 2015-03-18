
# Utility classes for dirfuzz

module Util

  cr = "\r"
  clear = "\e[0K"
  RESET = cr + clear

  def clear_line
    print RESET if $stdout.isatty
  end

  def remove_trailing_slash(base)
    # Check if it ends in a slash and if so remove it
    (base[-1] == "/") ? base.chop : base
  end

  def get_base_url(url)
    base = url.sub("http://", "")
    remove_trailing_slash(base)
  end

  class Code
    def initialize(get)
      @code = get.code
      @code_with_name = get.code_with_name
    end

    def redirect?
      @code == 301 || @code == 302
    end

    def found_something?
      @code != 404
    end

    def ok
      @code == 200
    end

    def forbidden?
      @code == 403
    end

    def ignore?(ignore_code)
      return false if ignore_code.instance_of? Fixnum
      ignore_code.scan(/\d+/).include? @code.to_s
    end

    def name
      @code_with_name
    end

    attr_reader :code
  end

  def print_output(msg, *colored_words)

    return if @options[:multi]

    output = OutputColor.new(colored_words, @options[:nocolors])

    # Subtitute color tags for colored words
    msg.gsub!(/%(\w+)/) { output.color($1) }

    puts msg

    # Remove colors when writing to a file
    @ofile.puts msg.gsub(/\e\[1m\e\[3.m|\[0m|\e/, '') if @options[:file]
  end

  def urldecode(input)
    input.gsub(/%([0-9a-fA-Z]{2})/i) { $1.hex.chr }
  end

  class OutputColor
    def initialize(words, coloring)
      @index = 0
      @words = words
      @coloring = coloring
    end

    def color(color_name)
      result = instance_eval "@words[@index].#{color_name}.bold"
      result = @words[@index] if @coloring == 1
      @index += 1
      return result
    end
  end
end
