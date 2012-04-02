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
      link = urldecode(link)
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
    web_extensions = %w[ htm html asp aspx jsp php py pl do / ]
    web_extensions.each do |extension|
     return true if link.include? extension
    end
    return false
  end

  def to_absolute (rel_links)
    host = host.chop if @host[-1] == "/"
    expanded_links = Array.new
    rel_links.each do |link|
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

  def normalize
    @abs_links.map { |link| link.sub('http://','') }
  end

  def puts_file(string)
    puts string
    @ofile.puts string if @ofile
  end

  def print_link(title,data)
    puts_file title

    if data == []
      puts_file 'nothing found.'
    else
      puts_file data
    end

    puts_file ''
  end

  def print_links(ofile)
    @ofile = ofile
    @abs_links = normalize
    final_links = @abs_links + to_absolute(@rel_links)
    final_links = final_links.sort.uniq { |link| link[/.*\?\w+/] } # Conseguir links con parametros unicos

    print_link "[External links]", @ext_links.sort.uniq
    print_link "[Absolute links]", @abs_links.sort.uniq { |link| link[/.*#\w+/] }
    print_link "[Relative links]", @rel_links.sort.uniq { |link| link[/(?:\/\w+)+/] }
    print_link "[E-mail accounts] (:mailto)", @mail_links.sort_by { |s| [ s[/@.*/], s[/.*@/] ] }.uniq.map { |m| m.sub('mailto:','') }
    print_link "[Parametized queries]", final_links.grep(/\?/)
  end

end
