
# Utility classes for dirfuzz

module Util

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
    
    def name
      @code_with_name
    end
  end

  def print_output (string,*array)
    index = 0
    
    if @options[:nocolors] == 0
      string.split.each do |word|
        case word
          when "%yellow"
          string.sub!("%yellow",array[index].yellow.bold)
          index += 1
          when "%green"
          string.sub!("%green",array[index].green.bold)
          index += 1
          when "%red"
          string.sub!("%red",array[index].red.bold)
          index += 1
        end
      end

    else 
      string.split.each do |word|
      case word
          when "%yellow"
          string.sub!("%yellow",array[index])
          index += 1
          when "%green"
          string.sub!("%green",array[index])
          index += 1
          when "%red"
          string.sub!("%red",array[index])
          index += 1
        end
      end
    end
    puts string
    @ofile.puts string.gsub(/\e\[1m\e\[3.m|\[0m|\e/,'') if @options[:file]
  end
  
  def urldecode(input)
  decoded = input + ""
  input.scan(/%[0-9a-f]{2}/i) do |h|
   ascii = h.split('%')[1].hex.chr
   decoded.gsub!(h,ascii)
  end
  return decoded
  end

end
