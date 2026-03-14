require "cgi"

module KomuraSoft
  module AutoInlineToc
    HEADING_PATTERN = /<h([2-4]) id="([^"]+)">([\s\S]*?)<\/h\1>/

    module_function

    def apply(document)
      return unless post_document?(document)
      return if document.output.to_s.empty?

      toc_label = document.data["lang"] == "en" ? "Contents" : "目次"
      return if document.output.include?(">#{toc_label}</h2>")

      headings = extract_headings(document.output)
      return if headings.empty?

      toc_html = build_inline_toc_html(toc_label, headings)
      document.output = document.output.sub(/(?=<h[2-4]\b)/, toc_html)
    end

    def post_document?(document)
      document.respond_to?(:collection) &&
        document.collection&.label == "posts" &&
        document.data["layout"] == "post"
    end

    def extract_headings(content_html)
      headings = []
      content_html.scan(HEADING_PATTERN) do |level, id, inner_html|
        headings << {
          level: level.to_i,
          id: id,
          text: normalize_text(strip_tags(inner_html))
        }
      end
      headings
    end

    def build_inline_toc_html(toc_label, headings)
      toc_heading_id = toc_label == "Contents" ? "contents" : "目次"
      +"<h2 id=\"#{toc_heading_id}\">#{toc_label}</h2>\n\n#{build_list_html(headings)}\n\n"
    end

    def build_list_html(headings)
      root = +"<ol>\n"
      stack = [{ level: 1, tag: "ol" }]

      headings.each_with_index do |heading, index|
        current_level = heading[:level]
        next_level = headings[index + 1]&.dig(:level)

        while stack.length > 1 && current_level <= stack.last[:level]
          root << "#{"  " * (stack.length - 2)}</#{stack.pop[:tag]}>\n"
          root << "#{"  " * (stack.length - 1)}</li>\n"
        end

        root << "#{"  " * (stack.length - 1)}<li>#{heading[:text]}"

        if next_level && next_level > current_level
          tag = "ul"
          root << "\n#{"  " * stack.length}<#{tag}>\n"
          stack << { level: current_level, tag: tag }
        else
          root << "</li>\n"
        end
      end

      while stack.length > 1
        root << "#{"  " * (stack.length - 2)}</#{stack.pop[:tag]}>\n"
        root << "#{"  " * (stack.length - 1)}</li>\n"
      end

      root << "</ol>"
      root
    end

    def strip_tags(html)
      html.gsub(/<[^>]+>/, "")
    end

    def normalize_text(text)
      CGI.unescapeHTML(text).gsub(/\s+/, " ").strip
    end
  end
end

Jekyll::Hooks.register :documents, :post_render do |document|
  KomuraSoft::AutoInlineToc.apply(document)
end
