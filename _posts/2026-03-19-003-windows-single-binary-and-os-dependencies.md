---
title: "Windows において、どこまでシングルバイナリにできるのか - 1 EXE にできる範囲、Windows 依存が残る場所、配布前の判断表"
date: 2026-03-19 10:00
lang: ja
translation_key: windows-single-binary-and-os-dependencies
tags:
  - Windows
  - 配布
  - シングルバイナリ
  - .NET
  - C++
  - WebView2
  - WinUI
description: "Windows アプリを 1 EXE に寄せたいとき、配布物を 1 個にすることと OS 依存を消すことの違いを、.NET、C++、WebView2、WinUI、サービス、ドライバまで整理します。"
consultation_services:
  - id: windows-app-development
    reason: "Windows アプリの配布では、single-file 化、ランタイム同梱、WebView2 や WinUI の採用判断、サービス化の是非まで含めて設計したほうが後戻りを減らせます。"
  - id: technical-consulting
    reason: "『1 EXE にしたい』という要望は、配布単位、OS 依存、登録要否、更新責任を分けて整理すると判断しやすくなります。"
---

この記事は、次の投稿から始まりました。

<script type="module" src="https://cdn.jsdelivr.net/npm/nostr-widgets/dist/nostr-widgets.js"></script><nostr-note data='{"content":"このまえ、雑談で「Windowsではどこまでをシングルバイナリと言っていいのか、NTDLLの先はどうか」みたいな話をしてたけど面白かった","created_at":1773882483,"id":"00ca8ead5c8600957b7bd4678a73673859b3cb3155ec887948b7498dbc2b7f5c","kind":1,"pubkey":"101b30ee88c27a13de68bf7c8c06368ea3e3e837641595c18675677d18a46a45","sig":"a980bf6a40e66054b927da92164e0be371555022a92f7bfa49cf386189da9e3633da7a163b46a14f0276693f91ab575a3ad72c68791807939ad83be23deefe17","tags":[["client","Damus"]]}'></nostr-note>

Windows で「できれば 1 ファイルで配りたい」は、かなり普通の要望です。社内ツール、装置連携ツール、監視端末、オフライン環境、インストーラを極力避けたい現場では、**シングルバイナリ化** はとても魅力があります。

ただ、この話は最初に整理しないと、だいたい途中で噛み合わなくなります。Windows で言う「シングルバイナリにしたい」には、実は次の 4 つが混ざりやすいからです。

- 配布物を 1 個にしたい
- .NET や Visual C++ のランタイムを事前インストール不要にしたい
- インストーラや管理者権限なしで置くだけで動かしたい
- 対象 Windows の違いに依存したくない

この 4 つは同じではありません。実務的には、こう考えるのが一番ずれません。

> **配布物を 1 EXE に寄せることはかなりできる。**  
> **でも、対象 Windows への依存をゼロにすることはできない。**

この記事では、その境界線を Windows アプリの実務向けに整理します。

## 1. まず結論

最初に結論だけまとめると、こうです。

- 普通のデスクトップ EXE なら、かなり高いところまで single binary 化できます
- ただし、**1 EXE にできること** と **対象 Windows に依存しないこと** は別です
- Shell 拡張、Windows サービス、ドライバ、WebView2、WinUI 3 の一部は、ファイル数より **OS へ何を登録し、何を前提にするか** のほうが本題になりやすいです
- 実務で一番大事なのは、**single binary 化したいのか、インストーラ不要にしたいのか、OS 依存を減らしたいのか** を分けて決めることです

言い換えると、Windows では次の線引きがかなり実務的です。

- 配布物を 1 個に寄せる: かなり可能
- 追加ランタイムを抱え込む: かなり可能
- xcopy 配布に寄せる: アプリ種別による
- 対象 Windows 側の依存を消す: 不可能

## 2. 「シングルバイナリ」は 4 段階に分けて考える

### 2.1 レベル A: 配布物が 1 個

一番表面的なのはこれです。

- メールで 1 個送れる
- USB に 1 個置けばよい
- 展開先に `app.exe` だけ置く

これは **見た目の配布単位** の話です。実際には起動時に一時展開していても、OS 側の DLL に依存していても、この条件だけなら満たせます。

### 2.2 レベル B: 言語ランタイムの事前インストールが不要

次は、対象マシンにあらかじめ .NET ランタイムや VC++ 再頒布可能パッケージを入れなくても動く状態です。

- C/C++ の静的リンク
- .NET の self-contained
- .NET の single-file
- .NET Native AOT

このレベルになると、「単体で持っていける」感じはかなり強くなります。

### 2.3 レベル C: インストールや登録が不要

ここから急に難しくなります。

単なる EXE なら、置くだけで動くことがあります。でも、次のようなものは別です。

- Shell 拡張
- Windows サービス
- カスタム URL スキームやファイル関連付け
- ドライバ
- Explorer や Office など、他プロセスに読み込まれるコンポーネント

この領域は **ファイルを置くだけ** では済みません。OS 側の登録や、ホスト側との結線が必要です。

### 2.4 レベル D: 対象 Windows に依存しない

これは Windows では無理です。

Windows アプリは最終的に Windows の API、ローダー、セキュリティモデル、デバイススタックの上で動くからです。single binary 化できるのは、**アプリ側の責任範囲まで** です。OS 自体まで持っていくわけではありません。

## 3. かなり 1 EXE にしやすい領域

Windows でも、次のようなアプリは比較的 1 EXE に寄せやすいです。

- 単独起動されるデスクトップツール
- EXE 自身が UI と処理を持つ業務アプリ
- 通信、ファイル処理、ログ収集、監視、装置制御のようなツール
- Explorer や Office のホスト統合を必要としないもの
- Web ランタイムを前提にしない UI

このタイプなら、アプリ本体に含めやすいものは多いです。

- 自前コード
- リソース
- マニフェスト
- 既定設定
- テンプレートデータ
- 一部のサードパーティ ライブラリ
- 言語ランタイム本体

さらに、DLL を完全に EXE 内へ埋め込まなくても、**EXE の隣に DLL を置く app-local 配布** は Windows では普通に有力です。実務では、

- `app.exe` 1 個
- または `app.exe` + 隣接 DLL 数個
- ただしインストーラ不要、管理者権限不要、xcopy で配れる

この形のほうが、無理に 1 EXE へ圧縮するより保守しやすいことがかなりあります。

## 4. 1 EXE でも消えない Windows 依存

「EXE 1 個なら、対象 Windows に依存しない」と思ってしまうと、ここで事故ります。実際には、1 EXE でも次の依存は残ります。

### 4.1 OS バージョン依存

Windows API にはそれぞれ最低サポート OS があります。x64 / Arm64 の違いもあります。つまり単一 EXE にしても、

- Windows 10 まで動くのか
- Windows 11 前提なのか
- Windows Server でも動かすのか
- x86 / x64 / Arm64 のどれを対象にするのか

は最初に固定する必要があります。

### 4.2 システム DLL 依存

こちらが 1 EXE にしたつもりでも、実行時には当然ながら OS 提供のコンポーネントを使っています。

- `kernel32.dll`
- `user32.dll`
- `advapi32.dll`
- COM 基盤
- サービス制御基盤

このあたりは Windows 側の責任範囲です。

### 4.3 セキュリティモデル依存

- UAC
- ファイル ACL
- サービス制御マネージャ
- レジストリ
- ドライバ署名ポリシー

こうしたものは、アプリが単独で抱え込めません。

### 4.4 ホストやランタイム依存

単独起動 EXE ではなく、何かのホストに載る設計だと依存は一気に増えます。

- WebView2 を使う: WebView2 Runtime が要る
- WinUI 3 / Windows App SDK を使う: 配布モードの整理が要る
- Shell 拡張を作る: Explorer 側への登録が要る

つまり、**UI や統合の選択が、そのまま配布の難しさになる** ことが多いです。

## 5. 技術別に見る現実的な落としどころ

### 5.1 ネイティブ C/C++

ネイティブ C/C++ は、single binary 化の自由度が高い側です。静的リンクを選ぶ余地があり、単独起動 EXE ならかなり寄せやすいです。

ただし、全部を 1 ファイルに押し込むことより、

- UCRT や VC++ ランタイムをどうするか
- サードパーティ DLL を app-local に置くか
- 対象 CPU / OS をどこまで絞るか

のほうが実務上は重要です。

### 5.2 .NET

.NET は `single-file`、`self-contained`、`Native AOT` があるので、見た目の配布単位はかなり小さくできます。

ただし区別は必要です。

- framework-dependent: 対象環境の .NET に依存
- self-contained: .NET ランタイムを抱える
- single-file: 配布物を 1 つへ寄せる
- Native AOT: さらに起動時依存を減らすが、機能制約もある

「single-file だから OS 依存が減る」わけではありません。減るのは主に **アプリ配布物のまとまり** です。

### 5.3 WebView2

WebView2 を採用すると、single binary の難しさはかなり変わります。ここでの本題は EXE の数ではなく、**WebView2 Runtime をどう扱うか** です。

正しい問いは「1 EXE にできるか」よりも、次です。

- Runtime を既存環境前提にするか
- Evergreen を使うか
- Fixed Version を同梱するか
- オフライン配布でどこまで責任を持つか

### 5.4 WinUI 3 / Windows App SDK

WinUI 3 も、採用した時点で配布要件が変わります。UI 技術の選択が、そのまま配布方式の選択になります。

single binary を最優先にするなら、**最初に UI 技術の前提を見直す** ほうが早いことがよくあります。

## 6. 本質的に「登録・依存」が必要な領域

### 6.1 Shell 拡張

Explorer に読み込まれる Shell 拡張は、単なる「置くだけ EXE」とは別物です。ここはファイル数より、**Explorer へどう登録するか** が本題です。

### 6.2 Windows サービス

サービス本体の exe 自体は 1 ファイルにできても、配布は別問題です。

- SCM への登録
- 権限
- 起動アカウント
- 復旧設定

を考える必要があります。つまりサービスは、「1 EXE にする」より「どうインストールするか」を詰める領域です。

### 6.3 ドライバ

ドライバはさらに明確です。INF、署名、インストール手順まで含めて成立するので、single binary の土俵に最初から乗りにくいです。

## 7. 実務での判断表

ざっくり判断するなら、次の表が使いやすいです。

| 作りたいもの | 1 EXE 現実度 | 先に考えるべきこと |
| --- | --- | --- |
| 単独起動の Win32 / C++ ツール | 高い | 静的リンク、対象 OS / arch |
| 単独起動の WinForms / WPF ツール | 高い | self-contained、single-file、Native AOT の適性 |
| WinUI 3 / Windows App SDK アプリ | 中 | 配布モード、追加依存 |
| WebView2 ベースのデスクトップ UI | 低から中 | Runtime の配布方式 |
| Explorer 右クリック拡張やプレビュー | 低い | COM / レジストリ登録 |
| Windows サービス | 中 | SCM 登録、権限、更新手順 |
| ドライバ同梱アプリ | 低い | INF、署名、インストール |

この表で一番大事なのは、**「バイナリの数」と「配布の責任範囲」は別** だと分かることです。

## 8. 配布設計で先に決めるべきこと

single binary 化を成功させたいなら、実装より前に次を決めたほうがうまくいきます。

### 8.1 何を 1 個にしたいのかを決める

- 配布物を 1 個にしたいのか
- ランタイム事前インストールをなくしたいのか
- インストーラ不要にしたいのか
- オフライン更新を簡単にしたいのか

この答えによって、選ぶ技術は変わります。

### 8.2 最低サポート Windows と arch を最初に固定する

single-file も Native AOT も、基本的に OS / architecture specific です。ここを曖昧にしたまま「とにかく 1 ファイルで」と進めると、最後に API 不足や runtime 不一致で詰まります。

### 8.3 「同梱するもの」と「Windows に任せるもの」を明文化する

実務では、この表を書いておくだけでかなり事故が減ります。

- アプリに同梱するもの
  - 本体 exe
  - 自前 DLL
  - 設定テンプレート
  - self-contained runtime
- Windows に任せるもの
  - システム DLL
  - OS API
  - SCM / レジストリ / Explorer
  - ドライバ基盤
- 別途前提とするもの
  - WebView2 Runtime
  - VC++ Redistributable
  - Office / Excel
  - 専用ドライバ

### 8.4 single binary を優先するなら、ホスト統合を減らす

これはかなり効きます。

- Shell 拡張をやめて普通の EXE にする
- サービス化せず、タスクスケジューラや明示起動で済ませる
- WebView2 ではなくネイティブ UI を使う
- COM は自プロセス内で閉じる

要するに、**OS に「読み込ませる」「登録する」設計を減らす** ほど、single binary に近づきます。

## 9. まとめ

Windows における single binary 化は、かなりのところまで可能です。ただし、正しい理解は次の一文に尽きます。

> **アプリを 1 EXE にすることはできる。**  
> **でも、そのアプリが依存する Windows まで 1 EXE にすることはできない。**

特に覚えておきたいのは次の 5 点です。

- 単独起動の普通の EXE なら、かなり 1 ファイル配布へ寄せられる
- C/C++ の静的リンク、.NET single-file、Native AOT は有力
- ただし OS バージョン、arch、システム DLL、セキュリティモデルへの依存は消えない
- Shell 拡張、サービス、ドライバ、WebView2、WinUI 3 の一部は、OS 登録や追加ランタイムの話が本体になる
- single binary の成否は、「何を 1 個にしたいのか」を最初に切り分けることで決まる

もし single binary を強く優先するなら、技術選定の時点で **OS との結合度を下げる** 方向で設計したほうが、はるかに成功しやすいです。

## 10. 参考資料

- Microsoft Learn, [Create a single file for application deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)
- Microsoft Learn, [Native AOT deployment overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- Microsoft Learn, [C runtime (CRT) and C++ standard library (STL) lib files](https://learn.microsoft.com/en-us/cpp/c-runtime-library/crt-library-features?view=msvc-170)
- Microsoft Learn, [Dynamic-link library search order](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-search-order)
- Microsoft Learn, [Targeting your application for Windows](https://learn.microsoft.com/en-us/windows/win32/sysinfo/targeting-your-application-at-windows-8-1)
- Microsoft Learn, [Creating Registration-Free COM Objects](https://learn.microsoft.com/en-us/windows/win32/sbscs/creating-registration-free-com-objects)
- Microsoft Learn, [Registering Shell Extension Handlers](https://learn.microsoft.com/en-us/windows/win32/shell/reg-shell-exts)
- Microsoft Learn, [CreateServiceW function](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-createservicew)
- Microsoft Learn, [Overview of INF Files](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/overview-of-inf-files)
- Microsoft Learn, [Windows driver signing tutorial](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/windows-driver-signing-tutorial)
- Microsoft Learn, [Distribute your app and the WebView2 Runtime](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)
- Microsoft Learn, [Windows App SDK deployment guide for self-contained apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
