
# Utility classes for dirfuzz

module Util

  cr = "\r"
  clear = "\e[0K"
  RESET = cr + clear

  def clear_line
    print RESET if $stdout.isatty
  end

  class Code
    def initialize(get)
      @code = get.code
      @code_with_name = get.code_with_name
    end

    def redirect?
      @code == 301 or @code == 302
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

    def ignore? (ignore_code)
      return false if ignore_code.instance_of? Fixnum
      @code == ignore_code.split(':')[1].to_i
    end

    def name
      @code_with_name
    end

    attr_reader :code
  end

  def print_output (msg,*colored_words)

    coloring = OutputColor.new(colored_words, @options[:nocolors])

    msg.split.each do |word|
      case word
        when "%yellow"
          msg.sub! "%yellow",coloring.color(:yellow)
        when "%green"
          msg.sub! "%green",coloring.color(:green)
        when "%red"
          msg.sub! "%red", coloring.color(:red)
        when "%blue"
          msg.sub! "%blue", coloring.color(:blue)
      end
    end

    puts msg
    @ofile.puts msg.gsub(/\e\[1m\e\[3.m|\[0m|\e/,'') if @options[:file]
  end

  def urldecode(input)
    decoded = input + ""
    input.scan(/%[0-9a-f]{2}/i) do |h|
      ascii = h.split('%')[1].hex.chr
      decoded.gsub!(h,ascii)
    end
    return decoded
  end

  class OutputColor
    def initialize(words,coloring)
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
