---
title: "VBA とは何か - 制約、将来性、置き換えるべき場面と現実的な移行パターン"
date: "2026-03-23T10:00:00+09:00"
author: "小村 豪"
tags:
  - VBA
  - Excel
  - Office
  - 既存資産活用・移行
  - Windows開発
excerpt: "VBA の基本、制約、今後の見通し、置き換えるべきケース、段階移行の進め方を整理します。"
---

# VBA とは何か - 制約、将来性、置き換えるべき場面と現実的な移行パターン

2026年03月23日 10:00 · 小村 豪 · VBA, Excel, Office, 既存資産活用・移行, Windows開発

VBA の相談では、次のような話がかなり混ざります。

- そもそも VBA って何なのか
- マクロは危ないと言われるが、もう使うべきではないのか
- これから使えなくなるのか
- Office Scripts や Power Automate に全部移せばよいのか
- 既存の `.xlsm` や Access 資産は残すべきか、捨てるべきか
- Excel を夜間バッチやサーバーで動かしてもよいのか

このへんは、1 つの答えで全部きれいに片づくテーマではありません。  
最初に見るべきなのは、**新しいか古いか** よりも、**どこで実行するのか、誰が使うのか、Excel / Access そのものが UI なのか、無人実行なのか** です。

この記事では、VBA とは何か、どこに制約があるのか、これから使えなくなるのか、置き換えるべき場面はどこか、どう段階移行すると現実的か、という順番で整理します。  
なお、内容は **2026 年 3 月時点** で確認できる Microsoft の公式情報を前提にしています。[^vba-ref][^excel-web-vba][^macro-block][^office-scripts-diff][^office-addins]

## 目次

1. まず結論
2. VBA とは何か
3. なぜ今でも使われるのか
4. VBA の主な制約
5. VBA はこれから使えなくなるのか
6. 置き換えるべきケース / 置き換えなくてよいケース
7. 現実的な置き換え先
8. 段階移行の進め方
9. よくある失敗
10. まとめ
11. 関連記事
12. 参考資料

---

## 1. まず結論

先に結論だけ並べると、だいたい次のようになります。

- VBA は **Office デスクトップアプリを拡張するためのイベント駆動言語** です。Excel や Word、PowerPoint、Access などの中で動くことが前提の技術です。[^vba-ref]
- 少なくとも 2026 年 3 月時点で、Microsoft の公式情報として **「VBA 自体を近いうちに終了する」** という明確なアナウンスは確認できません。いま起きているのは「突然の全廃」よりも、**使える場所と前提条件がはっきりしてきた** という変化です。[^vba-ref][^excel-web-vba][^macro-block][^office-scripts-diff]
- 具体的には、**Excel for the web では VBA を作成・実行・編集できません**。また、**インターネット由来ファイルのマクロは既定でブロック** されます。[^excel-web-vba][^macro-block]
- したがって、いまの論点は「VBA を全部捨てるか」ではなく、**どの領域を VBA に残し、どの領域を外へ出すか** です。
- 特に、**無人実行、サーバー実行、複数人運用、ブラウザ対応、中央配布、厳しい監査** が必要な処理は、VBA だけで抱え込まないほうが自然です。Microsoft も、Office のサーバー側自動化を推奨・サポートしていません。[^server-automation]
- 置き換え先は 1 つではありません。  
  **Excel を残すなら `.NET` DLL や別プロセスへ処理を逃がす**、**Microsoft 365 上の業務フローなら Office Scripts + Power Automate**、**クロスプラットフォーム拡張なら Office Add-ins**、**そもそも Excel が UI ではなくなっているなら Windows アプリや Web アプリへ出す**、という分け方が現実的です。[^office-scripts-diff][^office-addins][^server-automation]

要するに、**VBA は「即死する技術」ではなく、「適材適所がかなり明確な技術」** として見るのが実務的です。

## 2. VBA とは何か

VBA は **Visual Basic for Applications** の略で、Microsoft Office に付属する Visual Basic の一種です。Microsoft の公式ドキュメントでも、**Office アプリケーションを拡張するためのイベント駆動型プログラミング言語** と説明されています。[^vba-ref][^vba-64bit]

ここで重要なのは、VBA を **汎用のアプリ開発基盤** として見るより、**Office アプリの内側に差し込む拡張言語** として見るほうが実態に近い、という点です。

たとえば Excel なら、次のような対象に近い場所で動きます。

- `Workbook`
- `Worksheet`
- `Range`
- ボタンやフォーム
- ブックを開いたとき、保存したとき、セル変更時のイベント

つまり VBA の強みは、**Excel や Access の画面・帳票・ブック構造にとても近い** ことです。  
利用者がデスクトップの Office を開いて、ボタンを押して、ローカルファイルや共有フォルダのデータを処理して、そのまま帳票を出す。そういう **「利用者の手元で完結する自動化」** にはかなり強いです。[^vba-ref]

逆に言うと、VBA の本来の守備範囲は、最初から **サーバー、ブラウザ、モバイル、マルチテナントな Web システム** ではありません。

## 3. なぜ今でも使われるのか

VBA が今でも現場に残り続ける理由は、単に「古いから惰性で残っている」だけではありません。

まず、Excel や Access には、単なるデータではなく **業務手順そのもの** が入り込みやすいです。

- 帳票の見た目
- 印刷設定
- 入力チェック
- 月次処理の順番
- 部門ごとの例外ルール
- 現場が長年慣れた操作手順

このへんは、別システムへ移すときに「コード移植」だけでは済みません。  
**見た目、操作、例外、運用** が一体になっているので、VBA 資産は見た目以上に仕様を抱えています。

また、VBA は Office のオブジェクトモデルに近いため、利用者の目の前にある Excel そのものを操作して結果を返す、という用途では手数が少ないです。  
この近さは、後継候補を考えるときにも大事で、**単に新しい技術へ書き換えればそれで終わり** とは限りません。

実務では、次のように考えるのが自然です。

- **Excel が UI であり続けるなら**、VBA を一部残す価値がある
- **Excel は入出力だけでよいなら**、中身のロジックは外へ出しやすい
- **Excel 自体がもう本来の UI ではないなら**、作り直しの候補になる

## 4. VBA の主な制約

### 4.1 デスクトップ前提である

一番大きい制約はこれです。  
VBA は、基本的に **デスクトップ版 Office の内側** で動く技術です。

Microsoft の公式情報でも、**Excel for the web では VBA を作成・実行・編集できず、マクロ付きブックを開いて編集はできても、VBA の実行はできない** とされています。[^excel-web-vba][^office-web-service]

この時点で、次の要件とは相性が悪くなります。

- ブラウザで完結したい
- Mac / iPad / Web をまたいで同じ拡張を使いたい
- 管理者が中央配布したい
- ローカルの Excel デスクトップアプリに依存したくない

Microsoft 自身も、**複数プラットフォーム向けの拡張を作りたいなら Office Add-ins を見るべき** と VBA のドキュメント側で案内しています。[^vba-lang-ref][^office-addins]

### 4.2 セキュリティと配布の摩擦が大きい

VBA が「使えなくなった」と誤解されやすい理由のかなり大きい部分は、実は **セキュリティ強化** です。

Microsoft は、**インターネット由来のファイルに含まれる VBA マクロを既定でブロック** するようにしています。メール添付やダウンロードした `.xlsm` をそのまま開いても、昔より素直には実行されません。[^macro-block]

これはセキュリティとしては正しい方向です。  
ただし運用側から見ると、

- 添付で配ると動かない
- 社外サイトから落としたテンプレートが動かない
- OneDrive / SharePoint / ネットワーク経由での扱いが分かりにくい
- 「有効化してください」という案内が運用の弱点になる

という摩擦が増えます。

つまり、VBA の問題は「言語機能」だけではなく、**配布と信頼の設計** でも起きます。

### 4.3 32bit / 64bit の壁がある

Office は 32bit 版と 64bit 版があり、**Office 2019 と Microsoft 365 では既定が 64bit** です。[^vba-64bit]

そのため、古い VBA コードのうち、特に **Windows API を `Declare` で呼んでいるもの** は、64bit 環境でそのまま動かないことがあります。  
Microsoft も、`PtrSafe`、`LongPtr`、`LongLong` などを使って 32bit / 64bit の差を吸収する必要があると案内しています。[^vba-64bit]

ここでつらいのは、コードだけでなく、次の依存も一緒に問題になりやすいことです。

- 古い COM / ActiveX / OCX
- 32bit 前提の外部 DLL
- レジストリ登録前提の部品
- Office の参照設定ずれ

つまり、VBA の移行は **言語の書き換え** というより、**Office bitness と外部依存の整理** になることがかなり多いです。

### 4.4 無人実行・サーバー実行に向かない

ここはかなり重要です。  
Microsoft は、**Office アプリケーションのサーバー側自動化を推奨・サポートしていない** と明言しています。Office は、対話的なデスクトップとユーザープロファイルを前提に設計されており、無人環境では不安定やデッドロックが起き得ます。[^server-automation]

なので、次のような構成は危険寄りです。

- Windows サービスから Excel を起動する
- ASP.NET や DCOM から Office を自動化する
- タスクスケジューラ上で見えない Excel を延々回す
- サーバー上の Excel に帳票生成を丸投げする

「たまに動く」ことはあります。  
ただ、**動いていることと、支えられる構成であることは別** です。

無人実行が必要なら、まず疑うべきは VBA ではなく、**Excel アプリ自体を運転する構成** のほうです。

### 4.5 保守性・テスト性・差分管理で不利になりやすい

VBA は、ブックや Access ファイルの中にコードが閉じ込みやすいです。  
その結果、次の問題が起きやすくなります。

- どのファイルが正本なのか曖昧になる
- フォーム、シート、標準モジュールに責務が散る
- 参照設定や ActiveX 依存が環境ごとにずれる
- コードレビューや差分確認がしにくい
- 単体テストを作りにくい
- Excel のセル番地そのものが仕様化していく

これは VBA という言語だけの問題ではなく、**「Office ファイルの中に業務ロジックを持つ」構造の問題** です。  
小さな自動化では大きな問題にならなくても、業務システム化していくと急に効いてきます。

### 4.6 VBScript 依存がある場合は別の注意が必要

2025 年には、Microsoft 365 Developer Blog で **Windows における VBScript の段階的廃止が、VBA プロジェクトにも影響し得る** ことが案内されました。  
特に、**外部 `.vbs` を実行しているケース** や、**`VBScript.RegExp` の参照に依存しているケース** は影響対象になります。[^vbscript-deprecation]

一方で Microsoft は、**Microsoft 365 Version 2508（Build 19127.20154）以降の Windows 版 Office では RegExp クラスを VBA に既定で含める** 形でも対応を進めています。[^vbscript-deprecation]

ここで大事なのは、**VBScript の廃止と VBA の廃止は同じ話ではない** ということです。  
VBA そのものが消える話ではなく、**VBA からぶら下がっていた一部の外部依存を見直す必要がある**、という理解のほうが正確です。

## 5. VBA はこれから使えなくなるのか

結論から言うと、**「明日から全部使えなくなる」ではありません**。  
ただし、**「どこでも何にでも使える」時代でもありません**。

少なくとも Microsoft の公式情報の読み方として、いま強く見えるのは次の方向です。

- デスクトップ Office の拡張としての VBA は引き続き存在する[^vba-ref]
- Web / クロスプラットフォーム側は Office Scripts や Office Add-ins を使い分ける[^office-scripts-diff][^office-addins][^vba-lang-ref]
- マクロ配布の安全性は以前より厳しく扱う[^macro-block]
- VBScript 依存のような周辺部品は将来の影響を受け得る[^vbscript-deprecation]

さらに、Microsoft は Office Scripts について、**VBA はデスクトップ中心、Office Scripts は安全でクロスプラットフォームなクラウドベースのソリューション向け** だと明示しています。  
同時に、**デスクトップ クライアントで使える Excel 機能のカバー範囲は、現時点では VBA のほうが広い** とも説明しています。[^office-scripts-diff]

この 2 つを並べると、かなり実務的な見え方になります。

- **デスクトップ Excel の深い操作** では、まだ VBA の守備範囲が広い
- **ブラウザ / M365 / 共有ワークフロー** では、Office Scripts や Add-ins のほうが自然
- だから、**「全部 Office Scripts に変えればよい」でも、「VBA を永久に中心に置けばよい」でもない**

要するに、VBA の将来は **消滅よりも境界の明確化** と見るのが自然です。

## 6. 置き換えるべきケース / 置き換えなくてよいケース

まずは雑だけれど役に立つ判断表を置きます。

| 状況 | 判断の目安 | 理由 |
| --- | --- | --- |
| 利用者が自分の PC の Excel / Access を開いて使う、小規模な自動化 | そのまま使う、または軽く整理する | VBA の守備範囲にかなり合っています |
| Excel は UI と帳票だけ残したいが、ロジックが重くなっている | **ハイブリッド化** する | VBA は薄く残し、重い処理は `.NET` や別プロセスへ出したほうが保守しやすいです |
| ブラウザ、Mac、iPad でも使いたい | **VBA を中心にしない** | VBA はデスクトップ前提で、Office Add-ins はクロスプラットフォームです[^office-addins] |
| OneDrive / SharePoint 上のブックを、M365 ワークフローで回したい | **Office Scripts + Power Automate** を検討 | Office Scripts はクロスプラットフォーム / クラウド側の自動化向けです[^office-scripts-diff][^power-automate] |
| 夜間バッチ、サーバー、サービスで無人実行したい | **Excel 自動化をやめる** | Microsoft は Office のサーバー側自動化を推奨・サポートしていません[^server-automation] |
| 複雑な業務フロー、権限管理、監査、DB 連携が中心になっている | **アプリ化 / システム化** を検討 | Office ファイル内ロジックでは限界が来やすいです |

この表で大事なのは、**置き換えの判断軸が「VBA は古いから」ではない** ことです。  
本当に見るべきなのは、**実行環境、運用、配布、依存、監査、拡張性** です。

## 7. 現実的な置き換え先

### 7.1 Excel を残して、中身だけ `.NET` や別プロセスへ出す

いちばん現実的で失敗しにくいのは、これです。

- 画面や帳票の入口は Excel / Access のまま
- ボタンや入力フォームも当面そのまま
- ただし、業務ロジック、HTTP、暗号、CSV / JSON、重い計算、ファイル処理は外へ出す
- VBA は「橋渡し」と「UI 操作」だけに寄せる

この構成の利点は、**利用者の見た目と操作を壊しにくい** ことです。  
全面リプレイスよりも、まず **責務を薄くする** 方向で進められます。

KomuraSoft の記事でも、VBA から `.NET 8` の DLL を COM 経由で型付き利用するパターンを紹介しています。

- [`.NET 8 の DLL を型付きで VBA から使う方法 - COM 公開 + dscom で TLB を生成する`](https://comcomponent.com/blog/2026/03/16/007-dotnet8-dll-typed-vba-com-dscom-tlb/)

「全部書き直す前に、まず重いところだけ逃がす」は、かなり実務向けです。

### 7.2 無人実行や帳票生成は、Office アプリ自動化ではなくファイル直接生成へ寄せる

Excel 帳票を夜間バッチやサービスで大量生成したいなら、まず疑うべきは「VBA が古いか」ではなく、**Excel アプリを起動していること自体** です。

Microsoft は、サーバー側での Office Automation を推奨していません。  
代わりに、**Open XML 形式などを使って Office ファイルを直接扱う方法** を推奨しています。[^server-automation]

つまり、要件が

- `.xlsx` を作りたい
- 定型帳票を大量に出したい
- PDF 化したい
- 夜間バッチで回したい

のようなものなら、選ぶべき軸は **Excel を運転するか** ではなく、**Excel ファイルを組み立てるか** です。

関連する記事:

- [`Excel 帳票出力をどう作るか - COM 自動化 / Open XML / テンプレート方式の判断表`](https://comcomponent.com/blog/2026/03/16/010-excel-report-output-how-to-build/)

### 7.3 Microsoft 365 上の業務フローなら Office Scripts + Power Automate

業務がすでに OneDrive / SharePoint / Teams / Outlook / Forms の上に寄っているなら、Office Scripts はかなり候補になります。

Microsoft は、**Office Scripts を安全でクロスプラットフォームなクラウドベースのソリューション向け** と説明しています。  
また、Power Automate と組み合わせることで、メールやフォームやスケジュールをトリガにして Excel 処理を自動化できます。[^office-scripts-diff][^power-automate]

ただし、ここも万能ではありません。

- Office Scripts は **Excel レベルのイベントをサポートしません**
- 実行は **手動開始** または **Power Automate からの呼び出し** が基本です[^office-scripts-diff]
- Power Automate 連携には **Microsoft 365 のビジネスライセンス** が必要です[^power-automate]
- `Run script` アクションには、**1 ユーザーあたり 1 日 1,600 回**、**同期処理 120 秒** などの制限があります[^office-scripts-limits]

つまり、Office Scripts は「VBA の置換物」より、**M365 上の自動化部品** と見たほうが正確です。

### 7.4 クロスプラットフォーム拡張が欲しいなら Office Add-ins

Word、Excel、Outlook などを **Windows / Mac / iPad / ブラウザ** で拡張したいなら、Office Add-ins が第一候補です。

Microsoft の公式ドキュメントでも、Office Add-ins は **HTML / CSS / JavaScript** で構築でき、**複数プラットフォームで動作し、中央配布にも向く** と説明されています。[^office-addins]

これは、たとえば次のような要件に向いています。

- 社内ポータルや基幹システムと Office をつなぎたい
- Outlook / Excel / Word に同じ UI やコマンドを出したい
- ユーザーの PC ごとのマクロ配布ではなく、管理者配布したい
- ローカルな `.xlsm` 配布モデルから離れたい

VBA とは土俵が違うので、**Excel の中にコードを書く** 感覚とはかなり変わります。  
その代わり、運用と配布はかなり整理しやすくなります。

### 7.5 Excel / Access 自体が本来の UI ではなくなっているなら、Windows アプリや Web アプリへ出す

次のような状態なら、VBA の延命より **アプリとして作り直す** ほうが自然です。

- 画面遷移や権限制御が増えすぎている
- DB、監査ログ、承認フロー、ユーザー管理が中心
- 外部機器連携や長時間処理がある
- Excel のセルやフォームが業務仕様書の代わりになってしまっている
- ブックを閉じたら状態管理が消えること自体がつらい

この場合、Windows 前提の業務ツールなら **C# / .NET のデスクトップアプリ**、利用者や端末が広いなら **Web アプリ** のほうが構造を素直にできます。

KomuraSoft のサービスで言えば、特に相性がよいのは次の領域です。

- [既存資産活用・移行支援](https://comcomponent.com/services/legacy-asset-migration/)
- [技術相談・設計レビュー](https://comcomponent.com/services/technical-consulting/)
- [既存 Windows ソフトの改修・保守](https://comcomponent.com/services/windows-modernization-maintenance/)

## 8. 段階移行の進め方

VBA の置き換えで一番危ないのは、**最初から全部を 1 つの新技術へ寄せようとすること** です。  
実務では、次の順番のほうがだいたい安全です。

### 8.1 まず資産台帳を作る

最初に洗い出したいのは、コード量そのものより **依存関係** です。

- どの `.xlsm` / `.xlam` / `.accdb` / `.mdb` があるか
- どれが実運用の入口か
- 参照設定に何が入っているか
- `Declare`、外部 DLL、COM / ActiveX / OCX は何か
- 32bit / 64bit の前提はどうなっているか
- どのマクロが誰のどの手順で使われているか
- 出力物は何か（Excel、CSV、PDF、印刷、メール送信など）

ここを曖昧にしたまま置き換えると、あとで「誰も触っていないと思ったマクロが月末だけ生きていた」みたいな事故が起きます。

### 8.2 コードを責務で分ける

次にやるのは、ファイル単位ではなく **責務単位** で分けることです。

- Excel / Access の UI 操作
- シート入出力
- 帳票レイアウト
- 業務ルール
- 外部 API / ファイル / DB I/O
- バッチ処理
- 印刷 / 配布

この分け方をすると、残すもの、薄くするもの、外へ出すものが見えやすくなります。

### 8.3 置き換え先を責務ごとに決める

おすすめしやすい分け方は次です。

- **UI とシート操作**: 当面 VBA に残す
- **業務ロジック**: `.NET` DLL、別プロセス、サービスへ出す
- **無人帳票生成**: Open XML や直接生成へ寄せる
- **M365 ワークフロー**: Office Scripts + Power Automate
- **クロスプラットフォーム UI**: Office Add-ins
- **業務システム化した領域**: Windows / Web アプリへ分離する

重要なのは、**移行先を 1 つに統一しないこと** です。  
VBA 資産の中身は、だいたい複数の責務が混ざっています。

### 8.4 先にインターフェイスを固める

移行を始める前に、最低限ここは決めておいたほうがよいです。

- 入力は何か
- 出力は何か
- エラー時にどう返すか
- どのシート、どの名前付き範囲、どのファイルパスを契約にするか
- どの時点で結果が確定したとみなすか

ここを決めないまま進めると、**セル番地そのものが API** になって壊れやすくなります。

### 8.5 並行稼働で比較する

特に帳票や集計は、いきなり切り替えないほうが安全です。

- 旧 VBA 版と新実装版を並行で出す
- 出力された `.xlsx` / CSV / PDF を比較する
- 日付、丸め、書式、印刷範囲の差を確認する
- 例外系と空データ系も試す

VBA 置き換えの事故は、たいてい「動くかどうか」ではなく、**数字や書式が静かにずれる** 形で起きます。

## 9. よくある失敗

### 9.1 「VBA は古いから、全部 Office Scripts へ」で始める

Office Scripts は有力ですが、Microsoft 自身が **VBA のほうがデスクトップ Excel 機能のカバー範囲が広い** と説明しています。  
さらに、**Office Scripts は Excel レベルのイベントをサポートしません**。[^office-scripts-diff]

なので、深い Excel デスクトップ依存のマクロを、そのまま横移しする発想は危険です。

### 9.2 無人実行なのに Excel 自体を起動し続ける

これはかなり多いです。  
動いている間は便利に見えますが、Microsoft は Office のサーバー側自動化を推奨していません。[^server-automation]

夜間バッチやサービスなら、**Excel を運転する** のではなく、**Excel ファイルを組み立てる** ほうへ寄せたほうが安全です。

### 9.3 画面、帳票、業務ルールを同時に全部変える

VBA 置き換えで本当に怖いのは、コード変換そのものより **業務仕様の取り落とし** です。  
Excel のシートや Access フォームには、コードに書かれていない運用ルールがかなり埋まっています。

全部を一気に変えると、「見た目は近いが月末だけ違う」みたいな事故が起きやすいです。

### 9.4 32bit / 64bit と外部参照を後回しにする

移行案件では、VBA コードそのものより、

- `Declare`
- 外部 DLL
- COM / ActiveX / OCX
- Office bitness
- 参照設定

が先に爆発することがかなりあります。  
ここを後ろに回すと、実装の終盤で一気につらくなります。[^vba-64bit]

### 9.5 VBScript の話と VBA の話を混同する

VBScript の段階的廃止は、VBA から見れば **一部依存の見直し** の話です。  
VBA 全体の終了と同じ意味ではありません。[^vbscript-deprecation]

ここを混ぜると、「VBA が終わるらしい」という雑な社内情報だけが独り歩きしやすくなります。

## 10. まとめ

VBA をひとことで言うと、**Office デスクトップアプリに密着した拡張言語** です。  
Excel や Access のすぐそばで、利用者の手元の業務を自動化するには、今でもかなり実用的です。[^vba-ref]

ただし、これからの実務で大事なのは、VBA を **万能な中心技術として扱わない** ことです。

- **ブラウザ / クロスプラットフォーム** が欲しいなら、Office Scripts や Office Add-ins を見る[^office-scripts-diff][^office-addins]
- **無人実行 / サーバー処理** なら、Office Automation を避ける[^server-automation]
- **重いロジックや外部連携** は `.NET` や別プロセスへ出す
- **Excel / Access がもう UI として苦しい** なら、Windows アプリや Web アプリへ出す

要するに、答えは **「全部置き換える」でも「何も変えない」でもなく、「責務ごとに分けて、段階的に薄くする」** です。

VBA 資産は、雑に見ると古く見えます。  
ただ、実務ではその中に **業務仕様、運用手順、帳票設計、現場の慣れ** がかなり詰まっています。

だからこそ、置き換えは **翻訳** ではなく、**整理** として進めるのが一番安全です。

## 11. 関連記事

- [COM / ActiveX / OCX とは何か - 違いと関係をまとめて解説](https://comcomponent.com/blog/2026/03/13/000-what-is-com-activex-ocx/)
- [`.NET 8 の DLL を型付きで VBA から使う方法 - COM 公開 + dscom で TLB を生成する`](https://comcomponent.com/blog/2026/03/16/007-dotnet8-dll-typed-vba-com-dscom-tlb/)
- [`Excel 帳票出力をどう作るか - COM 自動化 / Open XML / テンプレート方式の判断表`](https://comcomponent.com/blog/2026/03/16/010-excel-report-output-how-to-build/)

## 12. 参考資料

[^vba-ref]: Microsoft Learn, [Office VBA Reference](https://learn.microsoft.com/en-us/office/vba/api/overview/). “Office Visual Basic for Applications (VBA) is an event-driven programming language that enables you to extend Office applications.”
[^vba-lang-ref]: Microsoft Learn, [Visual Basic for Applications (VBA) の言語リファレンス](https://learn.microsoft.com/ja-jp/office/vba/api/overview/language-reference). 複数プラットフォーム向けの拡張を作る場合は Office Add-ins を参照するよう案内されています。
[^excel-web-vba]: Microsoft Support, [Work with VBA macros in Excel for the web](https://support.microsoft.com/en-us/office/work-with-vba-macros-in-excel-for-the-web-98784ad0-898c-43aa-a1da-4f0fb5014343). Excel for the web では VBA の作成・実行・編集はできません。
[^office-web-service]: Microsoft Learn, [Office for the web service description](https://learn.microsoft.com/en-us/office365/servicedescriptions/office-online-service-description/office-online-service-description). Excel for the web では VBA マクロの作成・実行はできませんが、VBA を保持したブックの編集は可能です。
[^macro-block]: Microsoft Learn, [Macros from the internet are blocked by default in Office](https://learn.microsoft.com/en-us/microsoft-365-apps/security/internet-macros-blocked). インターネット由来ファイルの VBA マクロは既定でブロックされます。
[^vba-64bit]: Microsoft Learn, [64-bit Visual Basic for Applications overview](https://learn.microsoft.com/en-us/office/vba/language/concepts/getting-started/64-bit-visual-basic-for-applications-overview). Office 2019 / Microsoft 365 では 64bit が既定で、`PtrSafe`、`LongPtr` などの対応が必要になる場合があります。
[^office-scripts-diff]: Microsoft Learn, [Differences between Office Scripts and VBA macros](https://learn.microsoft.com/en-us/office/dev/scripts/resources/vba-differences). VBA はデスクトップ中心、Office Scripts は安全でクロスプラットフォームなクラウドベースのソリューション向けであり、現時点ではデスクトップ Excel 機能のカバー範囲は VBA のほうが広いと説明されています。
[^power-automate]: Microsoft Learn, [Run Office Scripts with Power Automate](https://learn.microsoft.com/en-us/office/dev/scripts/develop/power-automate-integration). Power Automate と Office Scripts を組み合わせた自動化、および必要ライセンスについて。
[^office-scripts-limits]: Microsoft Learn, [Platform limits, requirements, and error messages for Office Scripts](https://learn.microsoft.com/en-us/office/dev/scripts/testing/platform-limits). Power Automate 連携時の呼び出し回数やタイムアウトなどの制限について。
[^office-addins]: Microsoft Learn, [Office Add-ins platform overview](https://learn.microsoft.com/en-us/office/dev/add-ins/overview/office-add-ins). Office Add-ins は HTML / CSS / JavaScript ベースで、Windows、Mac、iPad、ブラウザをまたいで動作し、中央配布にも向きます。
[^server-automation]: Microsoft Support, [Considerations for server-side Automation of Office](https://support.microsoft.com/en-us/topic/considerations-for-server-side-automation-of-office-48bcfe93-8a89-47f1-0bce-017433ad79e2). Microsoft は Office のサーバー側自動化を推奨・サポートしておらず、Open XML などの代替手段を勧めています。
[^vbscript-deprecation]: Microsoft 365 Developer Blog, [Prepare your VBA projects for VBScript deprecation in Windows](https://devblogs.microsoft.com/microsoft365dev/how-to-prepare-vba-projects-for-vbscript-deprecation/). VBScript の段階的廃止が `.vbs` 実行や `VBScript.RegExp` 依存の VBA プロジェクトへ与える影響、および Office Version 2508 以降での RegExp 対応について。
