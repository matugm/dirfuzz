# Crawler module for Dirfuzz, limited to 1 level of depth.

require 'nokogiri'

class Crawler

  def parse (html)
    html = Nokogiri::HTML.parse(html) unless html.kind_of? Nokogiri::HTML::Document
    a_tags = html.xpath("//a[@href]")
   #form_tags = html.xpath("//form[@action]")  # Parsing of form tags, not implemented yet.
    links = []
    a_tags.each { |a| links << a[:href]  }
    links = links.sort.uniq
    return links
  end

  def initialize(host,html)
    @host = host + ""

    @links = parse html

    @abs_links = []
    @ext_links = []
    @rel_links = []
    @mail_links = []
  end

  def run(level)
    split_links @links

    if level > 0
      to_crawl = []
      to_crawl += filtered_absolute_links()
      to_crawl += expanded_relative_links()

      crawled_links = crawl(to_crawl)
      split_links crawled_links
    end
    @rel_links.delete_if { |link| link == "/" }
  end

  def filtered_absolute_links
    html_files = []
    @abs_links.each do |link|
      html_files << link if html? link
    end
    return html_files
  end

  def expanded_relative_links
    host = host.chop if @host[-1] == "/"
    expanded_links = []
    @rel_links.each do |link|
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

  def base_dir(link)
    topdir = link.scan(/\/\w+\//)[0]
    @rel_links << topdir if topdir
  end

  def split_links(links)
    links.each do |link|
      link = urldecode(link)
      link.sub!(/#.*/,'')
      if (link.index %r[http(s)?://#{@host}]) == 0
        @abs_links << link
      elsif (link.index %r[http(s)?://]) == 0
        @ext_links << link
      elsif link.start_with? "mailto:"
        @mail_links << link
      elsif html? link
        @rel_links << link
        base_dir link
      else
        base_dir link
      end
    end
  end

  def html? (link)
    return true if link.start_with? "/" and link.scan(/\.[\w]{1,5}$/) == []
    web_extensions = %w[ htm html asp aspx jsp php py pl do ]
    web_extensions.each do |extension|
      return true if (link.end_with? '.' + extension or link.end_with? '/')
    end
    return false
  end


  def crawl(to_crawl)
    crawled_links = []
    to_crawl.each do |link|
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

  def formated_links(type)
    case type
    when "external"
      @ext_links = @ext_links.sort.uniq
    when "absolute"
      @abs_links.sort.uniq { |link| link[/.*\?(?:\w+=)(?=\d+)|[\w\/.-]+/] }
    when "relative"
      @rel_links = @rel_links.sort.uniq { |link| link[/.*\/?(?:[\w_-]+)/] }
      @rel_links.map { |e| e.gsub(/^\/\w+\/\w+/) { |link| " "*4 + link  } }
    when "mail"
      @mail_links = @mail_links.sort_by { |s| [ s[/@.*/], s[/.*@/] ] }
      @mail_links.uniq.map { |m| m.sub('mailto:','') }
    when "robots"
      Http.open(@host + '/robots.txt').body.scan(/Disallow: (.*)/).sort.uniq
    end
  end

  def print_links(ofile)
    @ofile = ofile
    @abs_links = normalize
    final_links = @abs_links + expanded_relative_links()
    final_links = final_links.sort.uniq { |link| link[/.*\?\w+/] } # Conseguir links con parametros unicos

    print_link "[External links]",  formated_links('external')
    print_link "[Absolute links]",  formated_links('absolute')
    print_link "[Relative links]",  formated_links('relative')
    print_link "[E-mail accounts]", formated_links('mail')
    print_link "[Robots.txt]",      formated_links('robots')
    print_link "[Links with parameters]", final_links.grep(/\?/)
  end
end
