---
title: Windows において、どこまでシングルバイナリにできるのか - 1 EXE にできる範囲、Windows 依存が残る場所、配布前の判断表
date: 2026-03-19
tags:
  - Windows
  - 配布
  - シングルバイナリ
  - .NET
  - C++
  - WebView2
  - WinUI
summary: Windows アプリを「1 ファイルで配りたい」と考えたとき、配布物を 1 EXE にすることと、対象 Windows への依存を消すことは別問題です。本稿では、ネイティブ C/C++、.NET の single-file / Native AOT、Windows App SDK、WebView2、COM / サービス / ドライバを例に、どこまでをアプリ側に抱え込めて、どこからは対象 Windows の機能や登録、ランタイムに依存せざるを得ないのかを整理します。
---

# Windows において、どこまでシングルバイナリにできるのか - 1 EXE にできる範囲、Windows 依存が残る場所、配布前の判断表

Windows で「できれば 1 ファイルで配りたい」は、かなり普通の要望です。
社内ツール、装置連携ツール、監視端末、オフライン環境、インストーラを極力避けたい現場。そういう場面では、**シングルバイナリ化**はとても魅力があります。

ただ、この話は最初に整理しないと、だいたい途中で噛み合わなくなります。

Windows で言う「シングルバイナリにしたい」には、実は次の 4 つが混ざりやすいからです。

- **配布物を 1 個にしたい**
- **.NET や Visual C++ のランタイムを事前インストール不要にしたい**
- **インストーラや管理者権限なしで置くだけで動かしたい**
- **対象の Windows の違いに依存したくない**

この 4 つは同じではありません。
そして Windows では、実務的にはこう考えるのが一番ズレません。

> **配布物を 1 EXE に寄せることはかなりできる。**
> **でも、対象 Windows への依存をゼロにすることはできない。**

特に、単なるユーザー起動の EXE ではなく、Explorer 連携、COM ホスト統合、Windows サービス、ドライバ、WebView2、WinUI 3 まで入ってくると、話は「ファイル数」より **OS に何を登録し、何を前提にするか** のほうが本体になってきます。

この記事では、その境界線を実務向けに整理します。

## 目次

1. [まず結論](#1-まず結論)
2. [「シングルバイナリ」は 4 段階に分けて考える](#2-シングルバイナリは-4-段階に分けて考える)
3. [かなり 1 EXE にしやすい領域](#3-かなり-1-exe-にしやすい領域)
4. [1 EXE でも消えない Windows 依存](#4-1-exe-でも消えない-windows-依存)
5. [技術別に見る、シングルバイナリ化の現実](#5-技術別に見るシングルバイナリ化の現実)
6. [本質的に「対象 Windows への登録・依存」が必要な領域](#6-本質的に対象-windows-への登録依存が必要な領域)
7. [実務での判断表](#7-実務での判断表)
8. [配布設計で先に決めるべきこと](#8-配布設計で先に決めるべきこと)
9. [まとめ](#9-まとめ)
10. [参考資料](#10-参考資料)

## 1. まず結論

最初に結論だけまとめると、こうです。

- **普通のデスクトップ EXE なら、かなり高いところまでシングルバイナリ化できます。**
  - ネイティブ C/C++ なら静的リンクの選択肢があります。[^msvc-crt]
  - .NET でも single-file や Native AOT があります。[^dotnet-single-file][^dotnet-native-aot]
- ただし、**1 EXE にできること** と **対象 Windows に依存しないこと** は別です。
  - OS バージョン
  - CPU アーキテクチャ
  - システム DLL
  - UAC / サービス制御マネージャ / レジストリ / ドライバ モデル
  - インストール済みのホストやランタイム
  には、どうしても依存が残ります。[^windows-targeting][^dll-search]
- **Explorer 連携、サービス、ドライバ、ブラウザ UI、WinUI 3 の一部機能** まで入ると、
  「1 ファイルにできるか」より「OS へ何を登録する必要があるか」が重要になります。[^shell-ext][^service][^driver-inf][^webview2-distribution][^windows-app-sdk]
- 実務で一番大事なのは、
  **シングルバイナリ化したいのか、インストール不要にしたいのか、OS 依存を減らしたいのか** を分けて決めることです。

言い換えると、Windows では次の線引きがかなり実務的です。

- **配布物を 1 個に寄せる**: かなり可能
- **追加ランタイムを抱え込む**: かなり可能
- **管理者権限なし・xcopy 配布に寄せる**: アプリ種別による
- **対象 Windows 側の依存を消す**: 不可能

## 2. 「シングルバイナリ」は 4 段階に分けて考える

この話がややこしくなるのは、「1 ファイル」という言葉に複数の意味が入っているからです。

### 2.1 レベル A: 配布物が 1 個

一番表面的なのはこれです。

- メールで 1 個送れる
- USB に 1 個置けばよい
- 展開先に `app.exe` だけ置く

これは **見た目の配布単位** の話です。
実際には、起動時に一時展開していることもありますし、OS 側の DLL やサービスに依存していても、この条件だけなら満たせます。

### 2.2 レベル B: 言語ランタイムの事前インストールが不要

次は、対象マシンにあらかじめ .NET ランタイムや VC++ 再頒布可能パッケージを入れなくても動く状態です。

- C/C++ の静的リンク
- .NET の self-contained
- .NET Native AOT

このレベルになると、かなり「単体で持っていける」感じが出てきます。[^msvc-crt][^dotnet-single-file][^dotnet-native-aot]

ただし、ここまで来ても **Win32 API やシステム DLL への依存** は残っています。

### 2.3 レベル C: インストールや登録が不要

ここから急に難しくなります。

単なる EXE なら、置くだけで動くことがあります。
でも、次のようなものは別です。

- Shell 拡張
- Windows サービス
- カスタム URL スキームやファイル関連付け
- ドライバ
- Office や Explorer など、他プロセスに読み込まれるコンポーネント

この領域は **ファイルを置くだけ** では済みません。
OS 側の登録や、ホスト側との結線が必要です。[^shell-ext][^service][^driver-inf]

### 2.4 レベル D: 対象 Windows に依存しない

これは Windows では無理です。

理由は単純で、Windows アプリは最終的に Windows の API、ローダー、セキュリティ モデル、デバイス スタックの上で動くからです。Windows API の各ドキュメントには minimum supported client があり、アプリ側の manifest で supportedOS を宣言する話も出てきます。[^windows-targeting]

つまり、**シングルバイナリ化できるのはアプリ側の責任範囲まで** です。
OS 自体までアプリが持っていくわけではありません。

## 3. かなり 1 EXE にしやすい領域

Windows でも、次のようなアプリはかなり 1 EXE に寄せやすいです。

- 単独起動されるデスクトップ ツール
- EXE 自身が UI と処理を持つ業務アプリ
- 通信、ファイル処理、ログ収集、監視、装置制御のようなツール
- Explorer や Office のホスト統合を必要としないもの
- ブラウザ ランタイムを前提にしない UI

このタイプなら、アプリ本体に含めやすいものは多いです。

- 自前コード
- リソース
- マニフェスト
- 既定設定
- テンプレート データ
- 一部のサードパーティ ライブラリ
- 言語ランタイム本体

さらに、DLL を完全に EXE 内へ埋め込まなくても、**EXE の隣に DLL を置く app-local 配布** は Windows では普通に有力です。DLL の検索順序では、既知の DLL や API set などを除けば、アプリケーションの読み込み元フォルダーが探索対象に入ります。[^dll-search]

ここで大事なのは、**シングルバイナリの目標を「厳密に 1 ファイル」だけに置かない** ことです。

実務では、

- `app.exe` 1 個
- または `app.exe` + 隣接 DLL 数個
- ただしインストーラ不要、管理者権限不要、xcopy で配れる

この形のほうが、無理に 1 EXE へ圧縮するより保守しやすいことがかなりあります。

## 4. 1 EXE でも消えない Windows 依存

「EXE 1 個なら、対象 Windows に依存しない」と思ってしまうと、ここで事故ります。

実際には、1 EXE でも次の依存は残ります。

### 4.1 OS バージョン依存

Windows API にはそれぞれ最低サポート OS があります。さらに、Windows 8.1 以降を正しくターゲットするには、manifest の `<compatibility>` に `supportedOS` を宣言する話もあります。[^windows-targeting]

つまり、単一 EXE にしても、

- Windows 10 までは動くのか
- Windows 11 前提なのか
- Windows Server でも動かすのか
- x86 / x64 / Arm64 のどれを対象にするのか

は、最初に固定する必要があります。

### 4.2 システム DLL 依存

Windows の DLL ローダーは、Known DLLs や API set、SxS manifest、システム フォルダーなどを含めたルールで解決します。[^dll-search]

つまり、こちらが 1 EXE にしたつもりでも、実行時には当然ながら OS 提供のコンポーネントを使っています。

- `kernel32.dll`
- `user32.dll`
- `advapi32.dll`
- API set
- COM 基盤
- サービス制御基盤

あたりは、Windows 側の責任範囲です。

### 4.3 セキュリティ モデル依存

- UAC
- ファイル ACL
- サービス制御マネージャ
- レジストリ
- ドライバ署名ポリシー

のようなものは、アプリが単独で抱え込めません。

たとえばサービスは `CreateService` によって SCM データベースへ登録されますし、ドライバは INF ベースのドライバ パッケージと署名が前提です。[^service][^driver-inf][^driver-signing]

### 4.4 ホストやランタイム依存

単独起動 EXE ではなく、何かのホストに載る設計だと、依存は一気に増えます。

- WebView2 を使う → WebView2 Runtime が必要[^webview2-distribution][^webview2-runtime]
- WinUI 3 / Windows App SDK を使う → 配布モードと追加パッケージ依存を確認[^windows-app-sdk]
- Shell 拡張を作る → Explorer 側へ登録が必要[^shell-ext]

つまり、**UI や統合の選択が、そのまま配布の難しさになる** ことが多いです。

## 5. 技術別に見る、シングルバイナリ化の現実

ここからは、よくある技術スタックごとに見ます。

### 5.1 ネイティブ C/C++ は、いちばん 1 EXE に寄せやすい

Windows ネイティブの単独 EXE は、やはり一番シングルバイナリ化しやすいです。

MSVC では `/MD` と `/MT` の違いがまず重要です。`/MD` は DLL 版ランタイムを使い、`/MT` は UCRT / vcruntime / STL を静的リンクします。MSVC のドキュメントでも、`libucrt.lib` や `libvcruntime.lib` が `/MT` に対応することが明記されています。[^msvc-crt]

実務では、ざっくりこう整理できます。

- **/MT**
  - ランタイムを自分のバイナリに取り込みやすい
  - 配布は単純になりやすい
  - ただし DLL 境界で CRT 状態が分かれる話など、設計上の注意がある[^msvc-crt]
- **/MD**
  - 対象マシンに Visual C++ Redistributable が必要
  - もしくは再頒布 DLL を app-local 配置する必要がある[^vc-redist]

さらにややこしいのは UCRT です。
UCRT は Windows 10 以降では OS コンポーネントで、Microsoft は app-local 配置を「可能だが非推奨」としており、しかも Windows 10 / 11 ではシステム ディレクトリの UCRT が常に使われるとしています。[^ucrt]

つまり、C/C++ で言う「ランタイムをどこまで自前で持つか」はかなりコントロールできますが、**Windows 自身が持っている CRT / DLL ローダー / システム DLL の層は Windows 側** です。

とはいえ、

- 普通の EXE
- Shell 統合なし
- Web ランタイムなし
- ドライバなし

という条件なら、ネイティブ C/C++ は Windows で最も素直にシングルバイナリへ寄せやすい選択肢です。

### 5.2 .NET single-file は強いが、「見た目 1 ファイル」と「実行時 1 ファイル」は分けて考える

.NET の single-file 配布は、framework-dependent と self-contained の両方で利用できます。さらに single-file アプリは **OS とアーキテクチャ固有** です。[^dotnet-single-file]

ここで重要なのは、`.NET の single-file = 何でも完全に 1 ファイル` ではないことです。

Microsoft のドキュメントでは、

- managed DLL は bundle に含められる
- ただしネイティブ runtime バイナリは別扱いになることがある
- `IncludeNativeLibrariesForSelfExtract=true` を使うと 1 出力ファイルへ寄せられる
- その場合、Windows では `%TEMP%/.net` 配下へ展開して起動する

という点が説明されています。[^dotnet-single-file-details]

つまり、.NET single-file は **配布物としては 1 個** に見えても、

- 起動時に一時展開がある
- ファイル パス前提の API が壊れる
- 依存ライブラリの単一ファイル互換性に左右される

という注意があります。実際、`Assembly.Location` は空文字を返し、`Assembly.GetFile(s)` は例外になり得るので、パス前提のコードをそのまま持ち込むとハマります。[^dotnet-single-file-details]

また、Microsoft は **managed C++ コンポーネントは single-file 配布に向きにくい** とも書いています。[^dotnet-single-file-details]

なので .NET single-file はかなり強いのですが、正しい理解はこうです。

> **.NET single-file は「配布単位を 1 個にする」技術として強い。**
> **ただし実行時の挙動や API の意味まで普通の複数ファイル配布と同じではない。**

### 5.3 .NET Native AOT は「ランタイム事前インストール不要」にかなり強いが、制約は重い

.NET Native AOT は、アプリを self-contained でネイティブコードへ ahead-of-time コンパイルします。Microsoft のドキュメントでも、**.NET runtime が入っていないマシンで動かせる** と整理されています。[^dotnet-native-aot]

シングルバイナリ志向との相性はかなりよいです。

- 起動が速い
- .NET runtime 事前インストール不要
- 単独配布に寄せやすい

ただし、制約は無視できません。公式ドキュメントでは、Native AOT の制約として次が挙がっています。[^dotnet-native-aot-limits]

- `Assembly.LoadFile` のような **動的読み込み不可**
- `System.Reflection.Emit` のような **実行時コード生成不可**
- **C++/CLI 不可**
- **Windows では built-in COM なし**
- trimming 前提
- single-file 特有の既知の非互換を引き継ぐ

これはかなり本質的です。

つまり Native AOT は、

- 依存関係が素直
- reflection が重くない
- プラグイン的な動的ロードをしない
- COM 依存が薄い

というときは非常に強いですが、

- 古い COM 資産
- C++/CLI ブリッジ
- 実行時に DLL を差し替える構成
- heavy reflection

とは相性がよくありません。

**「.NET なのにネイティブ単体実行へかなり寄せられる」代わりに、動的さをかなり失う** のが Native AOT です。

### 5.4 Windows App SDK / WinUI 3 は self-contained にできても、「OS 依存なし」にはならない

Windows App SDK プロジェクトは既定では framework-dependent です。self-contained に切り替えること自体は可能で、`WindowsAppSDKSelfContained` を有効にすると、Windows App SDK Framework package の内容をアプリ側へ展開して配布できます。[^windows-app-sdk]

ここだけ見ると「では WinUI 3 も全部 1 EXE にできるのか」と思いがちですが、実務ではもう少し複雑です。

まず、公式ドキュメントにもある通り、

- packaged アプリなら **MSIX package の登録が必要**[^windows-app-sdk]
- unpackaged / external location なら **依存ファイルが EXE の隣へコピーされる**[^windows-app-sdk]

という違いがあります。

さらに、Windows App SDK の一部 API は追加の MSIX package に依存します。公式ドキュメントでは、少数の API が **critical OS functionality を表す追加 MSIX package** に依存すると説明されており、例として push notifications や app notifications が挙がっています。[^windows-app-sdk-extra]

つまり WinUI 3 / Windows App SDK は、

- **ランタイムの self-contained 化** はできる
- でも **配布全体が常に 1 EXE になるわけではない**
- 使う API によっては **OS 側パッケージ依存が残る**

という理解が実務的です。

### 5.5 WebView2 は「アプリ本体」と「Web ランタイム」を分けて考える必要がある

WebView2 を使うときは、最初から **純粋な single binary を諦める** くらいの感覚でいたほうが安全です。

公式ドキュメントでは、WebView2 アプリを配布するとき、**Evergreen と Fixed Version のどちらでもクライアントに WebView2 Runtime が存在することを確認する必要がある** とされています。[^webview2-distribution]

また、WebView2 Runtime には 2 つの配布モードがあります。[^webview2-runtime]

- **Evergreen**
  - ランタイムはアプリに同梱しない
  - 自動更新
  - 多くのケースで推奨
- **Fixed Version**
  - 特定バージョンの Runtime をアプリと一緒に配る
  - その Runtime はそのアプリ専用
  - 更新責任はアプリ側

ここで重要なのは、Fixed Version でも **「1 EXE に埋め込む」ではなく「アプリと一緒に配る」** ということです。[^webview2-runtime]

つまり、WebView2 を選んだ時点で、設計としてはこうなります。

> **アプリ本体を 1 EXE にすることはできても、Web プラットフォーム部分は別のランタイムとして扱う。**

Windows 11 では Evergreen Runtime が OS の一部として含まれますが、Microsoft 自身もエッジケースに備えて Runtime の存在確認を推奨しています。[^webview2-distribution][^webview2-runtime]

なので、WebView2 採用時の正しい目標は「pure single binary」ではなく、

- 実行前提を明示する
- Runtime 検出を入れる
- Evergreen か Fixed Version かを決める

の 3 点です。

## 6. 本質的に「対象 Windows への登録・依存」が必要な領域

ここは特に誤解されやすいところです。

### 6.1 COM は全部が悪者ではない。問題は「誰が起動するか」

COM という言葉が出ると、すぐ「登録が必要だから single binary は無理」と思われがちです。
でも、そこは少し雑です。

Microsoft のドキュメントにある通り、**Registration-Free COM** では activation context を使って、レジストリ登録なしで COM オブジェクトを使えます。[^regfree-com]

つまり、

- 自分の EXE が自分の COM コンポーネントを使う
- 起動主体が自分で、manifest も自分で制御できる

なら、COM でもかなり配布を単純化できます。

ただし、ここで一気に話が変わるのが **Shell 拡張** です。
Explorer に読み込まれる Shell extension handler は、Microsoft のドキュメントでも **登録が必要** と明記されています。[^shell-ext]

つまり COM そのものが問題なのではなく、

- **自分のプロセス内で閉じる COM** なのか
- **Explorer や他ホストに読み込ませる COM** なのか

で難しさが変わります。

### 6.2 Windows サービスは、バイナリ 1 個でも「配布 1 個」にはなりにくい

サービス本体の exe 自体は 1 ファイルにできるかもしれません。
しかし配布は別問題です。

`CreateService` は、サービス オブジェクトを作成して SCM データベースへ追加し、レジストリの `HKLM\System\CurrentControlSet\Services` に保存します。[^service]

つまりサービスは、

- バイナリの数
- SCM への登録
- 権限
- 起動アカウント
- 復旧設定

をセットで考える必要があります。

言い換えると、**サービスは「1 EXE にする」より「どうインストールするか」を詰める領域** です。

### 6.3 ドライバは、最初から single binary の土俵に乗りにくい

ドライバはさらに明確です。

Windows のドキュメントでは、INF はドライバ パッケージの一部であり、デバイス インストール コンポーネントがドライバをインストールするための情報を持つとされています。[^driver-inf]

さらに kernel-mode driver は、Windows で読み込まれるために **デジタル署名が必須** です。[^driver-signing]

つまり、ドライバを含む構成は最初から、

- `.sys`
- INF
- カタログ / 署名
- インストール手順

を考える必要があります。

ここは「1 EXE に押し込む」話ではありません。
**対象 Windows のドライバ モデルに正しく乗る** ことが本体です。

## 7. 実務での判断表

ざっくり判断するなら、次の表が使いやすいです。

| 作りたいもの | 1 EXE 現実度 | 追加で考えるべきこと |
|---|---:|---|
| 単独起動の Win32 / C++ ツール | 高い | `/MT` か `/MD` か、対象 OS / arch |
| 単独起動の WinForms / WPF ツール | 高い | .NET single-file / self-contained / Native AOT の適性 |
| WinUI 3 / Windows App SDK アプリ | 中 | packaged か unpackaged か、追加 MSIX 依存 |
| WebView2 ベースのデスクトップ UI | 低〜中 | WebView2 Runtime の配布方式 |
| Explorer の右クリック拡張やプレビュー ハンドラ | 低い | COM / レジストリ登録、アンインストール |
| Windows サービス | 中 | SCM への登録、権限、更新手順 |
| ドライバ同梱アプリ | 低い | INF、署名、インストール、サポート OS |

この表で一番大事なのは、**「バイナリの数」と「配布の責任範囲」は別** だと分かることです。

たとえば Windows サービスは、本体 exe 自体は 1 個にできます。
でも、それで「single binary deployment ができた」とは普通言いません。
配布の本体は SCM 登録や権限設計だからです。

同じように、WebView2 アプリも `app.exe` だけを見れば単体に寄せられますが、実際の配布責任は Runtime をどうするかまで含みます。

## 8. 配布設計で先に決めるべきこと

シングルバイナリ化を成功させたいなら、実装より前に次を決めたほうがうまくいきます。

### 8.1 何を 1 個にしたいのかを決める

最初に答えるべき問いはこれです。

- 配布物を 1 個にしたいのか
- ランタイム事前インストールをなくしたいのか
- インストーラ不要にしたいのか
- オフライン更新を簡単にしたいのか

この答えによって、選ぶ技術は変わります。

たとえば、

- **社内の単独ツール** なら Native AOT やネイティブ EXE が有力
- **Web 技術で UI を組みたい** なら WebView2 Runtime は受け入れる
- **Explorer 統合が必要** なら single binary を最優先目標にしない

のように、ゴールから逆算したほうが設計が安定します。

### 8.2 最低サポート Windows と arch を最初に固定する

single-file アプリも Native AOT も、基本的に OS / architecture specific です。[^dotnet-single-file][^dotnet-native-aot]

なので、

- Windows 10 x64
- Windows 11 x64 / Arm64
- Windows Server 2019

のどこを対象にするかは、要件の前半で固定したほうがよいです。

ここを曖昧にしたまま「とにかく 1 ファイルで」と進めると、最後に API 不足や runtime 不一致で揉めます。

### 8.3 「アプリに同梱するもの」と「Windows に任せるもの」を明文化する

実務では、この表を書いておくだけでかなり事故が減ります。

- **アプリに同梱するもの**
  - 本体 exe
  - 自前 DLL
  - 設定テンプレート
  - self-contained runtime
- **Windows に任せるもの**
  - システム DLL
  - OS API
  - SCM / レジストリ / Explorer
  - ドライバ基盤
- **別途前提とするもの**
  - WebView2 Runtime
  - VC++ Redistributable
  - Office / Excel
  - 専用ドライバ

この 3 分類がないと、「1 EXE のはずなのに動かない」という話がいつまでも終わりません。

### 8.4 single binary を優先するなら、ホスト統合を減らす

これはかなり効きます。

- Shell 拡張をやめて、普通の EXE から起動する
- サービス化せず、タスク スケジューラや明示起動で済ませる
- WebView2 ではなくネイティブ UI を使う
- COM ホスト統合ではなく、自前プロセス内で閉じる

要するに、**OS に「読み込ませる」「登録する」「常駐させる」設計を減らす** ほど、single binary に近づきます。

### 8.5 1 EXE にしたら、更新責任は自分に寄りやすい

これは見落とされがちです。

- .NET self-contained は、環境側の .NET セキュリティ パッチへ自動ロールフォワードしません。[^dotnet-publishing]
- WebView2 Fixed Version は、自分で Runtime を更新する責任があります。[^webview2-runtime]

つまり、**依存を抱え込むほど配布は簡単になるが、更新責任も自分に寄る** ということです。

single binary を採るかどうかは、ファイル数だけでなく、運用責任まで含めて決めるべきです。

## 9. まとめ

Windows におけるシングルバイナリ化は、かなりのところまで可能です。
ただし、正しい理解は次の一文に尽きます。

> **アプリを 1 EXE にすることはできる。**
> **でも、そのアプリが依存する Windows まで 1 EXE にすることはできない。**

特に覚えておきたいのは、次の 5 点です。

- **単独起動の普通の EXE なら、かなり 1 ファイル配布へ寄せられる**
- **C/C++ の静的リンク、.NET single-file、Native AOT は有力**
- **ただし OS バージョン、arch、システム DLL、セキュリティ モデルへの依存は消えない**
- **Shell 拡張、サービス、ドライバ、WebView2、WinUI 3 の一部は、OS 登録や追加ランタイムの話が本体になる**
- **single binary の成否は「何を 1 個にしたいのか」を最初に切り分けることで決まる**

実務での判断としては、こう考えるのが一番安全です。

- **配布物を 1 個にしたい** → かなり実現可能
- **対象マシンに余計な事前インストールをさせたくない** → 多くの場合実現可能
- **対象 Windows の違いを意識したくない** → 無理

そして、もし single binary を強く優先するなら、技術選定の時点で

- Web ランタイムを持ち込まない
- Explorer やサービスへの統合を減らす
- ドライバを別物として扱う
- COM は自プロセス内で閉じる

のように、**OS との結合度を下げる** 方向で設計したほうが、はるかに成功しやすいです。

## 10. 参考資料

[^dotnet-single-file]: [Microsoft Learn: Create a single file for application deployment - .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)
[^dotnet-single-file-details]: [Microsoft Learn: Single-file deployment（native libraries, extraction, API incompatibility）](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)
[^dotnet-publishing]: [Microsoft Learn: .NET application publishing overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/)
[^dotnet-native-aot]: [Microsoft Learn: Native AOT deployment overview - .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
[^dotnet-native-aot-limits]: [Microsoft Learn: Native AOT deployment overview - Limitations of Native AOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
[^msvc-crt]: [Microsoft Learn: C runtime (CRT) and C++ standard library (STL) lib files](https://learn.microsoft.com/en-us/cpp/c-runtime-library/crt-library-features?view=msvc-170)
[^vc-redist]: [Microsoft Learn: Latest Supported Visual C++ Redistributable Downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170)
[^ucrt]: [Microsoft Learn: Universal CRT deployment](https://learn.microsoft.com/en-us/cpp/windows/universal-crt-deployment?view=msvc-170)
[^dll-search]: [Microsoft Learn: Dynamic-link library search order](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-search-order)
[^windows-targeting]: [Microsoft Learn: Targeting your application for Windows](https://learn.microsoft.com/en-us/windows/win32/sysinfo/targeting-your-application-at-windows-8-1)
[^regfree-com]: [Microsoft Learn: Creating Registration-Free COM Objects](https://learn.microsoft.com/en-us/windows/win32/sbscs/creating-registration-free-com-objects)
[^shell-ext]: [Microsoft Learn: Registering Shell Extension Handlers](https://learn.microsoft.com/en-us/windows/win32/shell/reg-shell-exts)
[^service]: [Microsoft Learn: CreateServiceW function](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-createservicew)
[^driver-inf]: [Microsoft Learn: Overview of INF Files](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/overview-of-inf-files)
[^driver-signing]: [Microsoft Learn: Windows driver signing tutorial](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/windows-driver-signing-tutorial)
[^webview2-distribution]: [Microsoft Learn: Distribute your app and the WebView2 Runtime](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)
[^webview2-runtime]: [Microsoft Learn: Evergreen vs. fixed version of the WebView2 Runtime](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/evergreen-vs-fixed-version)
[^windows-app-sdk]: [Microsoft Learn: Windows App SDK deployment guide for self-contained apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
[^windows-app-sdk-extra]: [Microsoft Learn: Windows App SDK deployment guide for self-contained apps - Dependencies on additional MSIX packages](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
