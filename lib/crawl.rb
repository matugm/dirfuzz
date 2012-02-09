
# Crawler module for Dirfuzz, limited to 1 level of depth.

require 'nokogiri'

class Crawler

  def parse (html)
    html = Nokogiri::HTML.parse(html) unless html.kind_of? Nokogiri::HTML::Document
    a_tags = html.xpath("//a[@href]")
   #form_tags = html.xpath("//form[@action]")  # Parsing of form tags, not implemented yet.
    links = Array.new
    ext_links = Array.new
    a_tags.each { |a| links << a[:href]  }
    links = links.sort.uniq
    return links
  end

  def initialize(host,html)
    @host = host + ""
    #get = Http.open(@host)

    @links = parse html

    @abs_links = Array.new
    @ext_links = Array.new
    @rel_links = Array.new
    @mail_links = Array.new
  end

  def run(level)
    split_links @links
    @rel_links.delete_if { |link| link == "/" }

    if level > 0
      only_web = Array.new
      @abs_links.each do |link|
        only_web << link if html? link
      end
      only_web += to_absolute @rel_links

      crawled_links = crawl(only_web)
      split_links crawled_links
    end
end

  def split_links(links)
    links.each do |link|
      if link.start_with? "http://" + @host
        @abs_links << link
      elsif link.include? "http://"
        @ext_links << link
      elsif link.start_with? "mailto:"
        @mail_links << link
      elsif not link.include? ":" and not link.start_with? "#"
        @rel_links << link
      end
    end
  end

  def html? (link)
    web_extensions = %w[ htm html asp aspx php py pl do / ]
    web_extensions.each do |extension|
     return true if link.include? extension
    end
    return false
  end

  def to_absolute (rel_links)
    host = host.chop if @host[-1] == "/"
    web_extensions = %w[ htm html asp aspx php py pl do / ]
    expanded_links = Array.new
    rel_links.each do |link|
      link = urldecode link
      if html? link
        if link.start_with? "/"
          expanded_links << @host + link
        else
          expanded_links << @host + "/" + link
        end
      end
    end
    return expanded_links
  end

  def crawl(only_web)
    crawled_links = Array.new
    only_web.each do |link|
      html = Http.open(link)
      crawled_links += parse html.body
    end
    return crawled_links
  end

  def print_output(*string)
    string = string[0] || ""
    puts string
    @ofile.puts string if @ofile
  end

  def print_links(ofile)
    @ofile = ofile
    final_links = @abs_links + to_absolute(@rel_links)
    final_links = final_links.sort.uniq { |link| link[/.*\?\w+/] } # Conseguir links con parametros unicos

    print_output "---- External links"
    print_output @ext_links.sort.uniq
    print_output
    print_output "---- Absolute links"
    print_output @abs_links.sort.uniq { |link| link[/.*#\w+/] }
    print_output
    print_output "---- Relative links"
    print_output @rel_links.sort.uniq
    print_output
    print_output "---- E-mail accounts (:mailto)"
    print_output @mail_links.sort.uniq.map { |m| m.sub('mailto:','') }
    print_output
    print_output "**** Parametized queries"
    print_output final_links.grep(/\?/)
    print_output
  end

  end
