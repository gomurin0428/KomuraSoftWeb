---
title: "Windows の文字コードを整理する - なぜ文字化けが起きるのか、特に Linux と組み合わせたときに何がずれるのか"
slug: "windows-text-encoding-mojibake-linux"
date: "2026-03-21T10:00:00+09:00"
author: "小村 豪"
description: "Windows の文字コードを、なぜ文字化けが起きるのかという観点で整理します。CP932、UTF-8、UTF-16、BOM、console の code page、PowerShell、Linux の locale まで、実務で事故が増えやすいポイントをまとめます。"
tags:
  - Windows
  - 文字化け
  - UTF-8
  - CP932
  - Linux
  - PowerShell
  - Unicode
---

Windows の文字化けは、日本語が難しいから起きるわけではありません。ほとんどは、**同じバイト列を別の文字コードとして読んだ**か、**誤って読んだ結果を別の文字コードで保存した**ことが原因です。

特に Windows と Linux をまたぐと、Windows 側には CP932、UTF-8、UTF-16、console の code page、PowerShell の版差など複数の文脈が残り、Linux 側は UTF-8 前提で流れることが多いため、普段は見えていなかった前提のずれが一気に表面化します。

この記事では、Windows の文字コードまわりを「なぜ文字化けが起きるのか」という観点で整理し、特に Linux と組み合わせたときに事故が増えるポイントを実務向けにまとめます。

## 目次

1. まず結論
2. 文字化けの正体
3. なぜ Windows ではややこしくなりやすいのか
4. Linux と組み合わせたときの典型事故
5. 文字化け調査はこの 4 問で進める
6. 事故を減らす運用ルール
7. 最低限のチェックリスト
8. まとめ
9. 参考資料

## 1. まず結論

先に結論だけ書くと、重要なのは次の 6 点です。

- **文字化けは「文字」の問題ではなく、「バイト列をどう解釈したか」の問題**です。
- **Windows には Unicode 系と legacy code page 系が共存**しており、1 台の中でも文脈ごとに前提が違います。
- **Linux 側は UTF-8 前提が強い**ため、Windows 側の CP932 や UTF-16 が混ざると事故になりやすいです。
- **表示が崩れただけの段階**と、**壊れた内容を保存してしまった段階**は分けて考えるべきです。
- **新規テキストは UTF-8 を第一候補**にし、**既存の legacy ファイルは明示的な移行タスクまで現状維持**にするのが安全です。
- **file の encoding、editor の encoding、console の code page、アプリ内部の文字列形式は別物**です。ここを混同すると調査が迷子になります。

「Windows で文字化けした」という言い方だけでは、原因は特定できません。少なくとも次のどれがずれているかを分ける必要があります。

- ファイル自体の文字コード
- 保存時の文字コード
- エディタの解釈
- console の input/output code page
- アプリ内部の文字列形式
- Linux 側の locale と想定 encoding

## 2. 文字化けの正体

文字化けの正体は、かなり単純です。

1. 文字列をどこかの文字コードで **encode** してバイト列にする
2. そのバイト列をどこかの文字コードで **decode** して文字列に戻す
3. encode と decode の前提が一致しなければ、別の文字列として読まれる

たとえば、`あ` を UTF-8 で保存すると、バイト列は次になります。

```text
E3 81 82
```

このバイト列を UTF-8 として読めば `あ` ですが、CP932 側の文脈で読めば `縺�` のような別の文字列に見えます。  
これが、文字化けです。

大事なのは、ここで起きているのが「日本語が壊れた」ではなく、**同じ bytes に対する解釈がずれた**だけだという点です。

### 2.1 表示が崩れただけなら、まだ戻せることがある

文字化けには、まだ取り返せる段階があります。たとえば、**元の bytes が変わっていない**なら、正しい encoding で開き直せば戻せる場合があります。

逆に危ないのは、次のような流れです。

1. UTF-8 の file を CP932 として誤読する
2. 画面上では `縺�` のように見える
3. そのまま「見えている文字列」を保存する
4. もとの UTF-8 bytes が失われる

この段階に入ると、単なる表示崩れではなく、**データ破損**です。

### 2.2 さらに危ないのは「表現できない文字」を狭い code page に落とすとき

もう 1 つの典型事故は、Unicode 文字列を CP932 のような legacy code page に落とすときです。

たとえば、相手の code page に存在しない文字が含まれていると、

- `?` に置き換わる
- 置換文字 `�` が入る
- 近い別文字に変換される
- 変換失敗になる

といったことが起きます。

この事故は、**読める・読めない**だけでなく、**往復変換して元に戻るか**で見るべきです。  
一度失われた文字は、あとから正しい encoding を知っても復元できません。

## 3. なぜ Windows ではややこしくなりやすいのか

Windows がややこしいのは、単に古いからではありません。**Unicode の世界と legacy code page の世界が、いまも同居している**からです。

### 3.1 Windows API には Unicode 系と code page 系が共存している

Windows API には大きく 2 系統あります。

- `W` 系: wide character。Unicode を UTF-16 で扱う系
- `A` 系: ANSI と呼ばれる code page 系

つまり、Windows の中には最初から「Unicode で扱う道」と「その時点の active code page で扱う道」が両方あります。  
そのため、同じ Windows 上でも、**どの API やどのツールを通ったか**で前提が変わります。

### 3.2 「Windows の日本語」は 1 個ではない

Windows の日本語まわりで、実務上よく混ざるのは次の 4 つです。

- **CP932**: 日本語 Windows の legacy text でよく出る
- **UTF-8**: 新しい text 資産、web、cross-platform 系で増えている
- **UTF-16LE**: Windows 系ツールや API の文脈で今も普通に出てくる
- **console の code page**: cmd.exe や一部の console tool の入出力に効く別レイヤ

ここで大事なのは、**`chcp 65001` したから file も UTF-8 になった、ではない**ということです。  
console の code page を変えることと、既存 file の bytes が何かは別問題です。

なお、日本語 Windows の legacy text を雑に「Shift_JIS」と呼ぶことは多いですが、実務では **CP932 という名前で意識しておくほうが会話がぶれにくい**です。  
少なくとも「Windows 由来の日本語 legacy encoding の話をしている」と明示できます。

### 3.3 file 名と file 内容は別問題

Windows で日本語 file 名が普通に見えていると、「じゃあ中身も大丈夫だろう」と思いがちです。ここが危険です。

- path / file name を扱う層
- file の中身を読む層
- console に表示する層

この 3 つは別です。

たとえば、日本語 path は問題なく扱えても、file の中身は CP932 で保存されていて Linux 側で UTF-8 として読まれれば壊れます。  
逆に file の中身が UTF-8 でも、console の code page が合っていなければ表示だけ崩れます。

### 3.4 PowerShell や周辺ツールの既定値も揃っていない

Windows で地味に事故を増やすのが、**同じ「テキストを書いたつもり」でも経路によって出力 bytes が違う**ことです。

特に気をつけたいのは次です。

- **Windows PowerShell 5.1** は既定 encoding が一貫していない
- 一部 cmdlet や redirection は **UTF-16LE** を作る
- 別の経路では **active ANSI code page** が使われる
- **PowerShell 7 以降**は UTF-8 no BOM が既定になっている

つまり、「PowerShell で出した text」だけでは encoding は決まりません。  
**どの版で、どの cmdlet で、どの書き込み経路を使ったか**まで見ないといけません。

## 4. Linux と組み合わせたときの典型事故

Windows 単体だと何となく回っていたものが、Linux を挟んだ途端に壊れるのは珍しくありません。  
理由は単純で、Linux 側では **UTF-8 前提が強い**からです。

### 4.1 Windows で CP932 保存した text を Linux が UTF-8 として読む

一番よくある事故です。

- Windows の legacy app や古い運用が CP932 で CSV / TXT / log を書く
- Linux 側の script や tool は locale に従って UTF-8 前提で読む
- 結果として decode error、`�`、意味不明な文字列になる

このとき Linux 側の tool が悪いのではなく、**受け取った bytes に encoding の約束が付いていない**のが根本原因です。

### 4.2 Linux / VS Code で作った UTF-8 no BOM を Windows 側が ANSI と見なす

逆方向の事故もあります。

- Linux や VS Code で UTF-8 no BOM の script / config / text を作る
- Windows PowerShell 5.1 や legacy tool が BOM なし file を ANSI 側の code page と見なす
- 日本語や non-ASCII を含む行だけ壊れる

この事故は、**UTF-8 自体が悪い**のではなく、**BOM なし UTF-8 を正しく推定してくれない読み手**が混ざっていることが原因です。

### 4.3 Windows 側が UTF-16LE を書き、Linux 側では「テキストらしく見えない」

これもかなりあります。

- Windows PowerShell 5.1 の一部出力や legacy tool が UTF-16LE を書く
- Linux 側の text tool は UTF-8 の 1 byte stream を想定している
- 結果として NUL byte が大量に混ざった「バイナリっぽい text」になる

UTF-16LE 自体は悪くありません。  
ただし、**Linux の text processing tool にそのまま流す前提とは噛み合わない**場面が多いです。

### 4.4 BOM の有無でも friction が起きる

BOM は encoding そのものではありませんが、実務ではかなり効きます。

- Windows 側の一部 tool は BOM があると助かる
- Linux 側の一部 tool は BOM を先頭の余計な bytes として扱う
- 結果として 1 列目や 1 行目の先頭だけ壊れる、見えないゴミが付く、比較結果がずれる

特に UTF-8 では、**同じ UTF-8 でも BOM あり / なしで bytes は別物**です。  
「UTF-8 にした」だけでは、運用ルールとしてまだ半分しか決まっていません。

### 4.5 console の見え方を信じると迷う

Windows と Linux をまたぐとき、もう 1 つ危ないのが console です。

- Windows console には input / output の code page がある
- Linux terminal 側は UTF-8 locale 前提で動くことが多い
- WSL、SSH、container、CI を経由すると表示経路が増える

この状態で「console では読めたから file も大丈夫」「console では崩れたから file が壊れている」と判断すると外しやすいです。

**見えているものが壊れているのか、保存されている bytes が壊れているのかは、別に確認**したほうが安全です。

### 4.6 典型事故を表にするとこうなる

| 場面 | 実際の bytes | 読み手の想定 | 典型症状 |
|---|---|---|---|
| Windows の legacy app が保存した CSV | CP932 | Linux 側は UTF-8 | `�`、decode error、意味不明な日本語 |
| Linux / VS Code で作った file | UTF-8 no BOM | Windows PowerShell 5.1 が ANSI 扱い | 日本語行だけ壊れる |
| Windows PowerShell 5.1 の一部出力 | UTF-16LE または ANSI | Linux 側は UTF-8 text を期待 | NUL byte 混入、バイナリっぽい挙動 |
| UTF-8 with BOM の file | UTF-8 + BOM | Unix 系 tool は plain UTF-8 前提 | 先頭列だけ壊れる、余計な文字が付く |
| console 表示だけを信じる | file と console で別前提 | 調査者が表示だけで判断 | 原因切り分けを外す |

## 5. 文字化け調査はこの 4 問で進める

文字化け調査で迷ったら、私は次の 4 問に戻るのが一番早いと思っています。

### 5.1 元の bytes は何か

最初に見るべきは「今この file が何 bytes か」です。  
見た目ではなく、bytes を見る意識が必要です。

- UTF-8 か
- UTF-8 with BOM か
- CP932 か
- UTF-16LE か
- 途中で再保存されて別物になっていないか

### 5.2 最初に誰が、どの前提で書いたか

次に、「最初の書き手」を特定します。

- Windows の legacy app か
- PowerShell 5.1 か 7 か
- Linux の script か
- VS Code か
- Excel 由来の export か
- 何らかの middleware / batch / CI か

ここが曖昧なままだと、encoding 推定が運になります。

### 5.3 いま誰が、どの前提で読んでいるか

書き手だけでなく、**読み手の前提**も必要です。

- editor が auto-detect しているのか
- PowerShell が BOM を見ているのか
- Linux 側が locale に従って UTF-8 扱いしているのか
- library が既定 encoding を使っているのか
- 明示的に `Encoding.UTF8` や `cp932` を指定しているのか

文字化けは、ほぼここで発生します。

### 5.4 読み間違えた内容が、すでに保存されたか

最後に、**被害が表示だけで止まっているか**を確認します。

- まだ bytes は元のままか
- 壊れて見えている内容を誰かが保存したか
- `?` や `�` が差分に入っていないか
- 全文が別 encoding で書き直されていないか

この 4 問が埋まれば、たいてい原因は見えます。

## 6. 事故を減らす運用ルール

ここからは実務寄りの話です。  
Windows と Linux をまたぐ案件では、次のルールを最初に決めておくとかなり事故が減ります。

### 6.1 新規 file は UTF-8 を第一候補にする

新規の text file は、まず UTF-8 を第一候補にするのが無難です。  
ただし、ここで止まってはいけません。**BOM をどうするかも含めて決める**必要があります。

おすすめの考え方は次です。

- **Linux 側で読むことが多い text**: UTF-8 no BOM を基本にする
- **Windows の legacy tool や Windows PowerShell 5.1 が読む script**: BOM 有無を相手都合で明示する
- **UTF-16LE が必要な明確な相手**がいるなら、その要件を仕様として書く

「UTF-8 に統一」とだけ書くと、あとで BOM で揉めます。

### 6.2 既存 legacy file は、明示的な移行タスクまで維持する

既存 file が CP932 なら、日常の機能修正のついでに勝手に UTF-8 化しないほうが安全です。

安全なのは次の運用です。

- 既存 file は、**元の encoding / BOM / 改行**を維持する
- encoding 変更は、**移行タスクとして分離**する
- 変換対象、影響範囲、下流 consumer を確認してから一括変換する

文字化け事故の多くは、善意の「ついで UTF-8 化」から始まります。

### 6.3 encoding を interface の一部として扱う

CSV、TXT、log、設定 file、簡易 protocol は、内容だけでなく **encoding 自体が interface** です。

たとえば、仕様として最低限ここまでは書きたいです。

- この file は UTF-8 / CP932 / UTF-16LE のどれか
- UTF-8 の場合 BOM は付くか
- 改行は LF / CRLF のどちらか
- Linux / Windows のどちらが producer / consumer か
- 途中の batch や ETL が再保存しないか

「text で渡す」は仕様になっていません。

### 6.4 既定値を信用せず、書き込み時は明示する

code 上でも script 上でも、encoding は明示したほうが安全です。

危ない考え方は次です。

- 既定のまま保存する
- OS に合わせてたぶんいい感じになると思う
- console で読めたから file も大丈夫だろう
- auto-detect があるから大丈夫

既定値は、Windows / Linux、PowerShell 5.1 / 7、editor、runtime で普通に変わります。  
**明示しない限り、たまたま動いているだけ**になりやすいです。

### 6.5 console と file を分けて確認する

次はかなり効くルールです。

- console での表示確認
- file を再オープンしての確認

この 2 つを分けます。

`chcp` や terminal の表示が合っていても、保存 file が別 encoding なら意味がありません。  
逆に file は正常でも、console の表示 code page が合っていなければ見た目だけ壊れます。

### 6.6 Git は encoding を直してくれない

地味ですが大事です。

Git は基本的に **bytes を追跡する**だけです。  
つまり、壊れた bytes も、そのまま真面目に履歴へ入れます。

そのため、

- 何も変えていないのに巨大差分が出た
- 日本語の行だけ謎差分になった
- 先頭行だけ変わった
- 改行と encoding が一緒に変わった

というときは、内容変更より先に **re-encoding の事故**を疑ったほうがいいです。

## 7. 最低限のチェックリスト

最後に、Windows と Linux が混ざる案件で私なら最初に固定したいチェックリストを置きます。

### 7.1 編集前

- この file の現在の encoding は何か
- BOM はあるか
- 改行は LF / CRLF のどちらか
- 代表的な日本語行を 2〜3 個メモしたか
- Linux 側 / Windows 側のどちらが最終 consumer か分かっているか

### 7.2 編集中

- 既定 encoding に依存した書き込みをしていないか
- auto-detect 任せで save していないか
- PowerShell や shell redirection の経路を雑に使っていないか
- 「表示が読める」だけで安心していないか

### 7.3 編集後

- 保存後に再オープンして確認したか
- Linux 側でも Windows 側でも代表行が崩れていないか
- `?` や `�` が差分に増えていないか
- 先頭行や先頭列だけ壊れていないか
- BOM / 改行だけの大差分になっていないか

### 7.4 移行タスクとしてやるべきもの

- CP932 → UTF-8 の一括変換
- UTF-8 BOM policy の統一
- PowerShell 5.1 前提 script の棚卸し
- CI / container / WSL / SSH 経由の text pass の明文化
- editor / formatter / batch の保存設定の統一

## 8. まとめ

Windows の文字コード問題を一言で言うなら、**Unicode の世界と legacy code page の世界が、いまも同居していること**が本質です。

そして Linux と組み合わせたときに事故が増えるのは、Linux 側が UTF-8 前提で流れることが多く、Windows 側の CP932 や UTF-16、console code page、PowerShell の版差が一気に表に出るからです。

覚えておきたいのは次の 5 点です。

- 文字化けは bytes の解釈ずれ
- 表示崩れとデータ破損は別
- Windows では file / editor / console / API の層を分けて考える
- Linux とやり取りする text は UTF-8 を第一候補にする
- 既存 legacy file の変換は、通常改修と分ける

「Windows で文字化けした」をそのまま扱うと、話が広すぎます。  
でも、

- 元の bytes は何か
- 誰がどう書いたか
- 誰がどう読んだか
- すでに保存されたか

の 4 問で切れば、かなり整理できます。

文字コードは地味ですが、Windows と Linux の間では **I/O 契約そのもの**です。  
ここを曖昧にしないことが、いちばん効く対策です。

## 9. 参考資料

### Windows / Microsoft

- [Code Pages - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/intl/code-pages)
- [Code Page Identifiers - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers)
- [Unicode in the Windows API - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/intl/unicode-in-the-windows-api)
- [Console Code Pages - Windows Console | Microsoft Learn](https://learn.microsoft.com/en-us/windows/console/console-code-pages)
- [chcp | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/chcp)
- [Use UTF-8 code pages in Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/design/globalizing/use-utf8-code-page)

### PowerShell / VS Code

- [about_Character_Encoding | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding)
- [Understanding file encoding in VS Code and PowerShell | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/vscode/understanding-file-encoding)

### GNU / Linux locale

- [GNU gettext manual: Header Entry](https://www.gnu.org/software/gettext/manual/html_node/Header-Entry.html)
- [Debian Reference, Chapter 8. I18N and L10N](https://www.debian.org/doc/manuals/debian-reference/ch08.en.html)
