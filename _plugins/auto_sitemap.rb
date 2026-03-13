module KomuraSoft
  class AutoSitemapPage < Jekyll::PageWithoutAFile
    def initialize(site, entries)
      @site = site
      @base = site.source
      @dir = "/"
      @name = "sitemap.xml"

      process(@name)
      self.data = { "layout" => nil, "sitemap" => false }
      self.content = build_content(entries)
    end

    private

    def build_content(entries)
      lines = entries.map do |entry|
        <<~XML.chomp
          <url>
            <loc>#{entry[:loc]}</loc>
            <lastmod>#{entry[:lastmod]}</lastmod>
            <changefreq>#{entry[:changefreq]}</changefreq>
            <priority>#{entry[:priority]}</priority>
          </url>
        XML
      end

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        #{lines.join("\n")}
        </urlset>
      XML
    end
  end

  class AutoSitemapGenerator < Jekyll::Generator
    priority :lowest

    def generate(site)
      entries = []

      site.pages.each do |page|
        next if skip_page?(page)

        entries << build_entry(site, page, page.url)
      end

      site.posts.docs.each do |post|
        next if post.data["sitemap"] == false

        entries << build_entry(site, post, post.url)
      end

      entries.compact!
      entries.sort_by! { |entry| entry[:loc] }

      site.pages << AutoSitemapPage.new(site, entries)
    end

    private

    def skip_page?(page)
      return true if page.data["sitemap"] == false
      return true if page.url.nil? || page.url.empty?
      return true if page.url == "/sitemap.xml"
      return true if page.name == "404.html"

      false
    end

    def build_entry(site, item, url)
      source_path = resolve_source_path(site, item)
      lastmod = File.mtime(source_path).strftime("%Y-%m-%d")
      changefreq, priority = defaults_for(url, item)

      {
        loc: absolute_url(site, url),
        lastmod: lastmod,
        changefreq: changefreq,
        priority: priority
      }
    rescue StandardError
      nil
    end

    def resolve_source_path(site, item)
      candidates = []

      candidates << item.path if item.respond_to?(:path)
      candidates << item.relative_path if item.respond_to?(:relative_path)

      candidates.compact.each do |candidate|
        return candidate if File.exist?(candidate)

        absolute = File.expand_path(candidate, site.source)
        return absolute if File.exist?(absolute)
      end

      raise "source path not found for #{item.inspect}"
    end

    def absolute_url(site, url)
      site.config["url"].sub(%r{/\z}, "") + url
    end

    def defaults_for(url, item)
      return ["monthly", "1.00"] if url == "/"
      return ["weekly", "0.90"] if ["/blog/", "/en/blog/"].include?(url)
      return ["yearly", "0.30"] if url == "/privacy/"
      return ["monthly", "0.70"] if item.is_a?(Jekyll::Document)

      ["monthly", "0.50"]
    end
  end
end
