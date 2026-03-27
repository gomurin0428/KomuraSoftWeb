module KomuraSoft
  module ImageOptimization
    module_function

    def apply(document)
      return if document.output.to_s.empty?

      document.output = document.output.gsub(/<img\b(?![^>]*\bloading\s*=)([^>]*?)>/i) do |match|
        attrs = Regexp.last_match(1)
        "<img loading=\"lazy\" decoding=\"async\"#{attrs}>"
      end
    end
  end
end

Jekyll::Hooks.register :documents, :post_render do |document|
  KomuraSoft::ImageOptimization.apply(document)
end

Jekyll::Hooks.register :pages, :post_render do |page|
  next unless page.output_ext == ".html"

  KomuraSoft::ImageOptimization.apply(page)
end
