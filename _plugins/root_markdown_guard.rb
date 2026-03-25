module Jekyll
  module KomuraSoft
    class RootMarkdownGuard
      ALLOWED_ROOT_MARKDOWN = %w[
        case-studies.md
        company.md
        contact.md
        web-topics.md
        topics.md
        windows-software-examples.md
      ].freeze

      # 入力: site は現在の Jekyll サイト情報を持つ Jekyll::Site。
      # 出力: 許可されたルート Markdown 一覧を除いたファイル名配列を返す。
      # 処理内容: サイトのルート直下にある Markdown を列挙し、公開ページとして許可したもの以外を抽出する。
      def self.unexpected_root_markdown(site)
        Dir.glob(File.join(site.source, "*.md"))
          .map { |path| File.basename(path) }
          .reject { |file_name| ALLOWED_ROOT_MARKDOWN.include?(file_name) }
          .sort
      end

      # 入力: site は現在の Jekyll サイト情報を持つ Jekyll::Site。
      # 出力: なし。問題が無ければ何もしない。
      # 処理内容: 記事ソースの誤配置を検出したら、移動先を含むエラーメッセージでビルドを失敗させる。
      def self.validate!(site)
        unexpected_files = unexpected_root_markdown(site)
        return if unexpected_files.empty?

        raise Jekyll::Errors::FatalException, <<~MESSAGE
          Unexpected root Markdown files detected:
          - #{unexpected_files.join("\n- ")}

          Move article source files to docs/article-sources/ or _posts/.
        MESSAGE
      end
    end
  end
end

Jekyll::Hooks.register :site, :after_init do |site|
  Jekyll::KomuraSoft::RootMarkdownGuard.validate!(site)
end
