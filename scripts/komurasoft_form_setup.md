# KomuraSoft Google Forms セットアップ手順

この手順は、`scripts/komurasoft_form_setup.gs` を Google Apps Script で実行して、KomuraSoft 用のお問い合わせフォームをほぼ自動で組み立てるためのものです。

## いちばん安全な進め方

1. `https://script.google.com/` を開く
2. 新しいプロジェクトを作る
3. `scripts/komurasoft_form_setup.gs` の内容を丸ごと貼る
4. まずは `FORM_CONFIG.FORM_ID` を空のままにする
5. `buildKomuraSoftInquiryForm` を実行する
6. Google の権限承認を行う
7. 実行ログに出る `Form edit URL` と `Form published URL` を開いて確認する

この流れなら、新しいフォームが作られるので、既存フォームを壊しません。

最新スクリプトでは、各問い合わせ種別のセクションを回答後そのまま送信するように設定しています。
そのため、技術相談を選んだあとに開発依頼やその他のセクションまで進んでしまうことはありません。

## もしセクション見出しだけが表示される場合

スクリプトの古い版では、セクション区切りだけが先に作られ、質問が最後のセクションへ寄ってしまう不具合がありました。
その場合は、壊れたフォームを使い続けず、**最新スクリプトで新しく作り直す** のが安全です。

やること:

1. `scripts/komurasoft_form_setup.gs` を最新内容に置き換える
2. `FORM_CONFIG.FORM_ID` を空のままにする
3. `buildKomuraSoftInquiryForm` を実行する
4. 新しく出た `Form edit URL` を開く

## 既存フォームを直接作り直したい場合

既存フォームに回答が入っている場合は、まず Google Forms 側で複製してください。  
そのあとで、複製したフォームの ID を `FORM_CONFIG.FORM_ID` に入れて実行します。

追加で変更する値:

- `FORM_CONFIG.FORM_ID`
- `FORM_CONFIG.CLEAR_EXISTING_ITEMS = true`

回答が入っているフォームを直接消して作り直すのは危ないので、スクリプト側ではデフォルトで止まるようにしてあります。

## 実行後にログへ出るもの

- フォームの編集 URL
- 公開 URL
- 汎用問い合わせ URL
- `技術相談` が選択済みのプリフィル URL
- `技術相談 + 参考にした記事 / ページ` のテンプレート URL

汎用 URL は公開 URL をそのまま使い、プリフィル URL は Apps Script の正式な `toPrefilledUrl()` で生成します。
分岐付き質問があるため、内部では一時的に分岐なしの選択肢へ切り替えて URL を生成し、その後すぐ分岐設定を戻します。

## ブログ記事用のプリフィル URL を 1 本作る方法

1. `logArticlePrefilledUrl` を開く
2. `REPLACE_WITH_ARTICLE_TITLE_OR_URL` を記事タイトルまたは記事 URL に変える
3. 実行する
4. ログに出た URL を使う

## すでに作ったフォームの URL だけ取り直す方法

1. `FORM_CONFIG.FORM_ID` に既存フォームの ID を入れる
2. `logExistingFormUrls` を実行する
3. ログに出た
   - `Generic URL`
   - `Technical consultation URL`
   - `Article template URL`
   を使う

この関数はフォーム本体を作り直しません。
すでに作ったフォームの構造を使って、URL だけ再生成します。

## このスクリプトで作る内容

- 共通セクション
  - メールアドレス
  - お名前
  - 会社名 / 組織名
  - お問い合わせ種別
  - 参考にした記事 / ページ
- 技術相談セクション
- 開発依頼セクション
- 既存システムの改修・保守セクション
- その他セクション
- 完了メッセージ
- プリフィル URL

## このあとこちらでできること

フォーム作成後に、ログで出た URL をもらえれば、サイト側のリンクを

- 技術相談はこちら
- 開発依頼はこちら
- ブログ記事ごとの相談 CTA

へ差し替えられます。
