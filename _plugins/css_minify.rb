module KomuraSoft
  module CssMinify
    module_function

    def minify(css)
      output = css.dup.force_encoding("UTF-8")
      output.gsub!(%r{/\*.*?\*/}m, "")
      output.gsub!(/^\s+/, "")
      output.gsub!(/\s*\n\s*/, "")
      output.gsub!(/\s*([{}:;,>~+])\s*/, '\1')
      output.gsub!(/;(?=})/, "")
      output.gsub!(/\s{2,}/, " ")
      output.strip
    end
  end
end

Jekyll::Hooks.register :site, :post_write do |site|
  css_path = File.join(site.dest, "komura_soft_single_page.css")
  next unless File.exist?(css_path)

  original = File.read(css_path, encoding: "UTF-8")
  minified = KomuraSoft::CssMinify.minify(original)
  File.write(css_path, minified)

  saving = original.bytesize - minified.bytesize
  Jekyll.logger.info "CssMinify:", "#{css_path} — saved #{saving} bytes (#{(saving * 100.0 / original.bytesize).round(1)}%)"
end
