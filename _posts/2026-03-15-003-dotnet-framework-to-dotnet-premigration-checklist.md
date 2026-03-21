---
title: ".NET Framework を .NET に移行する前に確認するべきこと - 着手前で勝負が決まる実践チェックリスト"
date: 2026-03-15 16:00
lang: ja
translation_key: dotnet-framework-to-dotnet-premigration-checklist
tags:
  - .NET
  - .NET Framework
  - C#
  - モダナイゼーション
  - Windows開発
  - 移行
description: ".NET Framework から .NET へ移行する前に確認しておくべきポイントを実務目線で整理します。プロジェクト種別、移行できない技術、NuGet 依存関係、PackageReference、SDK スタイル、ASP.NET / WPF / WinForms / WCF / EF6、設定ファイル、CI/CD、運用まで、着手前に潰すべき論点をまとめます。"
consultation_services:
  - id: legacy-asset-migration
    reason: ".NET Framework、Web Forms、WCF、COM / ActiveX、古い NuGet 運用が絡む既存資産の整理なので、レガシー資産移行の相談テーマとして相性がよい内容です。"
  - id: technical-consulting
    reason: "移行スコープ、段階移行の切り方、Windows 専用前提をどこまで許容するかを着手前に整理したい場合は、技術相談・設計レビューとして進めやすいテーマです。"
---

[日英シート付きの Excel チェックリストをダウンロード](/assets/downloads/2026-03-15-dotnet-framework-to-dotnet-premigration-checklist.xlsx)

`.csproj` の `TargetFramework` を `net10.0` に変えて、NuGet を何個か更新して、ビルドが通ったら終わり。

……という移行なら、だいぶ平和です。実際にはそうならないことのほうが多いです。

.NET Framework の現場には、`System.Web`、WCF、Web Forms、古い `packages.config`、`web.config.install.xdt`、ネイティブ DLL、COM / ActiveX、設計時だけ動くサードパーティ製コントロール、暗黙の `x86` 前提、デザイナー依存の ResX、古いシリアライザーなど、普段は意識していない前提がかなり眠っています。

なので、.NET Framework から .NET への移行で本当に大事なのは、実装に入る前の棚卸しです。  
着手前に論点を分解できていれば、移行は「大きな賭け」ではなく「順番に潰す作業」になります。

この記事では、既存の **.NET Framework 4.x の業務アプリケーション** を **現在の .NET** に移行する前に、何を確認しておくべきかを整理します。主な対象は次です。

- クラスライブラリ
- コンソールアプリ
- Windows サービス
- WinForms / WPF
- ASP.NET Framework（MVC / Web API / Web Forms）
- WCF を使うアプリ
- EF6 を使うアプリ

執筆時点は **2026-03-15** です。サポート期間や公式ツールの推奨は変わるので、日付が離れて読まれる場合は公式情報もあわせて確認してください。

## 1. まず結論

最初に、外しにくい結論だけ置きます。

- **移行前に .NET Framework 側を整理する** のが先です。Microsoft の公式ガイドでも、移植前に **.NET Framework 4.7.2 以降** へ上げ、`PackageReference` 化、SDK スタイル化、依存関係更新を先に済ませることが推奨されています。
- 難易度は **コード量よりアプリモデル** で決まります。クラスライブラリやコンソールは比較的軽く、**ASP.NET Framework、Web Forms、WCF サーバー、WF** は重くなりやすいです。
- **WinForms / WPF は .NET に移行できても Windows 専用のまま** です。ここを勘違いすると、移行したのに Linux コンテナへ載らない、という定番の地雷を踏みます。
- **ASP.NET Framework → ASP.NET Core は実質アーキテクチャ移行** です。小規模アプリなら一気に行けることもありますが、大きな本番系は段階移行を前提にしたほうが安全です。
- **WCF と EF6 は、runtime の移行と切り離せることがあります。** WCF クライアントは .NET 用のサポートされたパッケージがありますし、EF6 は modern .NET へ移したあとで EF Core に分離移行できます。
- 一方で、**AppDomain 作成、.NET Remoting、CAS、COM+、Workflow Foundation、BinaryFormatter 依存** は赤信号です。先に見つけないと、後ろで工数が爆発します。
- **`packages.config` / `install.ps1` / `XDT` / `content` 資産 / ネイティブ DLL / COM / ActiveX / x86 前提** は、ビルドが通っても実行時や設計時で落ちやすいので、着手前に洗います。
- 2026-03 時点では **.NET 10 が LTS** です。新規移行の着地点は、基本的に **現行 LTS** を基準に考えるのが自然です。
- **テスト、計測、ロールバックの用意がない移行は危険** です。移行は実装作業というより、前提条件を一個ずつ可視化する作業です。

## 2. そもそも「今すぐ移行すべきか」を先に決める

最初にやるべきなのは、「移行する方法」を考えることではありません。  
**本当に今このアプリを移行すべきか** を決めることです。

ここを曖昧にすると、技術的には正しいけれど事業的には重すぎる移行、あるいは逆に、明らかに移行したほうがよいのに後回しにしすぎる判断になりがちです。

### 2.1 .NET Framework に残る判断も、普通にあり得る

.NET Framework 4.8.1 は、サポートされている Windows に載っている限り継続サポートされます。つまり、**今すぐ全部 modern .NET にしないと即危険** という単純な話ではありません。

ただし、残留には明確な制約があります。

- Windows 専用から出られない
- ASP.NET Web Forms や古いサーバースタックを抱え続ける
- 新しい .NET の性能改善、言語機能、エコシステムの恩恵を受けにくい
- クラウド、コンテナ、CI/CD の今どきの前提とズレやすい

逆に、次へ強く依存しているなら、**当面は .NET Framework 4.8.1 に寄せて安定運用しつつ、別ラインで置き換え計画を立てる** のは合理的です。

- Web Forms の画面資産が大量にある
- WCF サーバー互換を厳密に保つ必要がある
- Workflow Foundation や COM+ 依存が深い
- サードパーティの設計時部品が modern .NET 非対応
- ビジネス的に大きな仕様変更が許されない

### 2.2 選択肢ごとに、何が変わるか

| 選択 | 何が良くなるか | 何が残るか / 失うか | 向いているケース |
| --- | --- | --- | --- |
| .NET Framework 4.8.1 に留まる | 既存資産を崩さず安定運用しやすい | Windows 専用、古いアプリモデル、モダン化の限界 | 強いレガシー依存があり、今は事業優先で安定運用したい |
| modern .NET へ移行するが Windows に留まる | ランタイムやツールチェーンを modern 化できる。性能・開発体験・SDK スタイルの恩恵が大きい | Windows API 依存は残る。クロスプラットフォームにはならない | WinForms / WPF、Windows Service、Windows API を使う業務アプリ |
| modern .NET へ移行し、将来的に Linux / コンテナ / クラウドも視野に入れる | 配置先の自由度が上がる。運用モデルも新しくしやすい | Windows 専用 API や app model を先に剥がす必要がある | サーバーサイドをクラウド寄せしたい、インフラ刷新もしたい |

大事なのは、**移行したいか** ではなく **移行後にどこへ着地したいか** を先に決めることです。

## 3. 先に決めておくべき 4 つの方針

### 3.1 着地点の .NET バージョン

執筆時点では、Microsoft のサポートポリシー上、**.NET 10 が LTS** です。  
一方で **.NET 8 LTS** と **.NET 9 STS** は、どちらも **2026-11-10** にサポート終了予定です。

なので、これから新規に .NET Framework から移行するなら、よほどの事情がなければ **現行 LTS を着地点にする** のが自然です。

ここでの実務的な考え方はシンプルです。

- **短く済ませたい小さな移行** なら、現行 LTS に直接着地
- **長期運用前提の基幹システム** でも、やはり現行 LTS を基本に考える
- 「既存ライブラリの都合で 1 つ前の LTS にしたい」は事情としてあり得るが、**いつまで保守されるのか** を日付で見て判断する

### 3.2 Windows 専用のまま行くか、将来クロスプラットフォームを狙うか

この判断で、見るべき論点がかなり変わります。

- **Windows 専用のまま** なら、WPF / WinForms や Windows Compatibility Pack を使って、まずは runtime を modern 化する現実路線が取れます。
- **将来 Linux / コンテナ化も狙う** なら、`System.Drawing.Common`、レジストリ、WMI、EventLog、Windows Service、COM、Office Interop などの Windows 前提 API を早い段階で棚卸しする必要があります。

ここを決めずに移行を始めると、途中で「Windows 固定で良かったのか」「いや、コンテナへ載せたかったんだった」と話がねじれます。

### 3.3 一気にやるか、段階移行にするか

移行の型は大きく 3 つです。

- **in-place に近い一括移行**
- **side-by-side で新旧を並べる移行**
- **route / library 単位で少しずつ寄せる段階移行**

特に ASP.NET Framework アプリでは、Microsoft のガイドでも **incremental migration** が明確に案内されています。  
本番を止めたくない、機能数が多い、周辺依存が多い、という条件なら、最初から段階移行前提で設計したほうが無理がありません。

### 3.4 何を「今回の移行対象から外すか」

移行が失敗しやすいのは、やることを盛りすぎるからです。

たとえば、次を同時にやるのは重くなりがちです。

- .NET Framework → .NET
- ASP.NET Framework → ASP.NET Core
- EF6 → EF Core
- Windows サーバー → Linux コンテナ
- 認証基盤の変更
- ログ / 監視基盤の変更
- データベースの移行

もちろん全部いつかは必要かもしれません。  
ただし **同時にやる必要があるか** は別です。

現実には、次のように分離したほうがうまくいきます。

1. まず runtime とプロジェクト構造を modern 化する
2. その上で app model を移す
3. 最後に ORM、認証、クラウド、監視を更新する

## 4. 着手前に整えておく土台

Microsoft の移植前ガイドはかなり実務的です。  
要するに、**移行前に今の .NET Framework プロジェクトを modern な入口へ寄せておく** という話です。

### 4.1 .NET Framework 4.7.2 以降へ上げる

公式ガイドでは、移植前に **.NET Framework 4.7.2 以降** をターゲットにすることが推奨されています。  
理由は、.NET Standard が既存 API をそのまま持っていないときでも、より新しい API 代替へ寄せやすくなるからです。

実務では、可能なら **4.8.1** を基準に考えたほうが分かりやすいです。

- サポートの観点で素直
- .NET Framework 側の最終安定点として扱いやすい
- 「まず現行 Framework 側で整理する」という方針が立てやすい

#### これを先にやると何が変わるか

- `.NET Standard 2.0` 共有ライブラリの扱いが安定しやすくなる
- 古いランタイム由来のノイズを先に減らせる
- 互換性問題を「Framework の古さ」と「modern .NET 化」のどちらが原因か切り分けやすくなる

### 4.2 PackageReference へ寄せる

移植前ガイドでは、参照を **`PackageReference`** 形式へ寄せることが推奨されています。  
これを先にやっておくと、依存関係管理がかなり見通しよくなります。

#### PackageReference にすると何が変わるか

- パッケージ参照が `csproj` に集約される
- 推移的依存関係が見やすくなる
- restore の前提が modern .NET 側と揃う
- CLI / CI との相性が良くなる

ただし、ここには地雷があります。

#### 典型的な地雷

NuGet の公式ドキュメントには、`packages.config` から `PackageReference` への移行で次の制約が明記されています。

- **Visual Studio の built-in 移行は ASP.NET プロジェクトでは使えない**
- `install.ps1` / `uninstall.ps1` に依存するパッケージは、期待どおり動かないことがある
- `content` フォルダーの資産は無視されることがある
- `web.config.install.xdt` などの **XDT 変換は適用されない**
- `lib` 直下のアセンブリ構成が古いパッケージはうまく解決されないことがある

つまり、**パッケージ形式を変えるだけ** と思わないほうがよいです。  
特に classic ASP.NET は、NuGet パッケージのインストール時に `web.config` を書き換える文化がかなりあったので、移行時に暗黙の前提が露出しやすいです。

### 4.3 SDK スタイルへ寄せる

移植前ガイドでは、**SDK スタイルのプロジェクト形式** への変換も推奨されています。

これはかなり効きます。

#### SDK スタイルにすると何が変わるか

- `csproj` が大幅に簡潔になる
- `PackageReference` と相性が良い
- multi-targeting しやすい
- `dotnet build` / `dotnet test` / `dotnet publish` を中心にした CI/CD に寄せやすい
- modern .NET 側の構成に近づくので、後半の差分が減る

逆に言うと、**古い `csproj` と古い NuGet 管理のまま、いきなり modern .NET に飛ぶと差分が大きすぎる** ということです。

### 4.4 依存関係を先に更新する

これも公式ガイドどおりですが、依存関係は **利用可能な最新バージョン** へ寄せ、可能なら **.NET Standard 対応版** に寄せます。

#### これを先にやる意味

- 「このパッケージは modern .NET で使えるのか」が早く分かる
- 古い依存関係がノイズになるのを防げる
- shared library を `netstandard2.0` 化しやすくなる
- 後段の移行作業を「コードの移植」に集中させやすい

### 4.5 公式ツールの前提も確認しておく

2026-03 時点では、Microsoft の案内の重心は **GitHub Copilot モダン化** 側へ移っています。  
つまり、従来の移行支援ツールだけを前提にするより、評価、計画、コード修正、検証まで含めた一連の支援フローとして見たほうが実務に合います。

ただし、現行ドキュメントでは **Visual Studio 2026 またはサポート中の Visual Studio 2022 系**、**GitHub Copilot**、そして **C# コード** が前提になっています。

#### この確認が必要な理由

- 公式ツールへ何を期待できるかが変わる
- チームの IDE / build agent / 拡張機能の前提を揃えられる
- **VB.NET ソリューションでは自動化に期待しすぎない** という判断ができる

VB.NET が混ざる現場は珍しくありません。  
なので「最新の公式ツールがどこまで手伝ってくれるか」を、最初に確認しておく価値があります。

## 5. プロジェクト種別ごとの難易度を見積もる

移行は「.NET Framework から .NET へ」ひとまとめに語られがちですが、現実には **プロジェクト種別ごとに別ゲーム** です。

### 5.1 ざっくりした難易度感

| 種別 | 難易度感 | 主な論点 |
| --- | --- | --- |
| クラスライブラリ | 低〜中 | API 互換性、依存関係、ターゲット分割 |
| コンソール / バッチ / 一部の Windows Service | 低〜中 | 配布方式、ネイティブ依存、設定 |
| WinForms / WPF | 中 | Windows 専用のまま、デザイナー、サードパーティ UI、BinaryFormatter 周辺 |
| ASP.NET MVC / Web API | 中〜高 | ASP.NET Core への app model 移行、認証、セッション、設定、DI |
| ASP.NET Web Forms | 高 | 画面モデルの差が大きい、UI 層の置換前提 |
| WCF クライアント | 中 | パッケージ置き換え、契約、構成 |
| WCF サーバー | 高 | CoreWCF か gRPC / HTTP API 再設計か |
| EF6 → EF Core 同時実施 | 高 | ORM が別物、振る舞い差、移行履歴 |

### 5.2 クラスライブラリは「共有境界」をどう切るかが鍵

クラスライブラリは比較的移しやすいです。  
ただし、それは **本当にライブラリがライブラリらしく分離されているとき** に限ります。

以下のような依存があると、難易度は上がります。

- `System.Web` に触っている
- `HttpContext.Current` を直接見ている
- WPF / WinForms の型を公開 API に含んでいる
- レジストリ、WMI、EventLog など Windows API に寄りすぎている
- `AppDomain` や Remoting に依存している

**ビジネスロジックだけを切り出せるなら軽い、アプリモデルまで抱え込んでいると重い** と見ると分かりやすいです。

### 5.3 WinForms / WPF は移行しやすいが、Windows 専用のまま

WinForms と WPF は .NET に移行可能です。  
ただし、どちらも **Windows 専用フレームワークのまま** です。

ここで期待値を間違えると危険です。

- **良くなること**
  - modern .NET のランタイム、言語、SDK スタイルに乗れる
  - CI/CD や package 管理を今どきに寄せやすい
  - 一部の性能・保守性改善を得やすい
- **変わらないこと**
  - Windows 専用であること
  - UI コントロールや設計時部品の相性問題が残ること
  - ActiveX / COM / ネイティブ DLL 問題が消えないこと

また、**WinForms / WPF は BinaryFormatter の影響確認が要る** ケースがあります。  
特に clipboard、drag & drop、ResX、設計時のシリアライズに custom type が絡むと、target を .NET 9 以降へ上げたときに表面化しやすいです。

### 5.4 ASP.NET Framework は「runtime 移行」ではなく「app model 移行」

ASP.NET Framework から ASP.NET Core への移行は、Microsoft のガイドでも **non-trivial** と明言されています。  
これは単に API 名が変わるからではなく、**前提となるアーキテクチャが違う** からです。

違いが出やすいところは次のあたりです。

- Hosting model
- Middleware pipeline
- Request processing model
- Session / Cache
- Authentication / Authorization
- Configuration
- Dependency Injection
- Logging / Monitoring

つまり、ASP.NET Framework のアプリでやるべき確認は次です。

- どの route / endpoint から先に移せるか
- `System.Web` 依存を shared library から剥がせるか
- 認証 / セッション / 例外処理 / ログをどう揃えるか
- 本番を止めずに段階移行するか

特に大きいアプリは、最初から **incremental migration** 前提で考えたほうが現実的です。

### 5.5 Web Forms は「資産移行」ではなく「責務分解」から入る

Web Forms は、ASP.NET Core と同じ app model ではありません。  
なので、見積もり上は **画面資産をそのまま持っていける前提で考えない** ほうが安全です。

実務では、まず次の分解から入ることが多いです。

- 画面ロジックとビジネスロジックを分ける
- `Page` / `UserControl` / `ViewState` に埋まった責務を分解する
- 業務ロジックやデータアクセスを shared library へ逃がす
- UI は Razor Pages / MVC / Blazor など別モデルで再構成する

つまり Web Forms 案件は、**runtime の移行より先に責務の分解計画があるか** が重要です。

### 5.6 WCF クライアントと WCF サーバーは分けて考える

ここは一緒くたにしないほうがよいです。

#### WCF クライアント

WCF Client には、modern .NET 向けの **サポートされた NuGet パッケージ** があります。  
なので、**WCF を呼ぶ側だけなら、見た目ほど重くない** ケースがあります。

#### WCF サーバー

一方で、WCF サービスを **ホストする側** は別です。  
Microsoft のガイドでは、modern 化の経路として大きく次の 2 つが案内されています。

- **CoreWCF** を使って既存クライアント互換を保つ方向
- **gRPC** など modern な RPC / HTTP ベースへ寄せる方向

ただし CoreWCF は **WCF のすべてをそのまま持ってくるわけではなく、サブセット** です。  
つまり、既存クライアントとの互換維持には向きますが、**コード変更とテストは前提** です。

## 6. .NET で使えない / そのままでは詰まりやすい技術を洗う

これは着手前に絶対やっておきたいところです。  
Microsoft には **.NET Framework で使えたが、.NET 6+ では使えない技術** の一覧があります。

### 6.1 赤信号になりやすい技術

| 技術 | .NET での状態 | どう考えるべきか |
| --- | --- | --- |
| `AppDomain.CreateDomain` など AppDomain の作成 | 非対応 | 分離は別プロセス / コンテナ / `AssemblyLoadContext` で考える |
| .NET Remoting | 非対応 | IPC、HTTP、gRPC、Socket、Pipe などへ再設計 |
| CAS / Security Transparency | セキュリティ境界として非対応 | OS / コンテナ / 権限分離で考える |
| `System.EnterpriseServices`（COM+） | 非対応 | COM+ 前提の設計を分離・置換する |
| Workflow Foundation | 非対応 | CoreWF など代替を含め、別見積もりで考える |
| WCF server | built-in ではそのままではない | CoreWCF か gRPC かを選ぶ |
| BinaryFormatter | .NET 9 以降では実装が常に例外 | シリアライザー移行、ResX / clipboard / drag & drop 監査 |

### 6.2 AppDomain は「一部 API が残っていても、作成は別問題」

AppDomain 周辺は少しややこしいです。  
`.NET` でも一部 API surface は残っていますが、**新しい AppDomain を作って隔離する** という使い方はサポートされていません。

そのため、以下の用途で AppDomain を使っていた場合は再設計が必要です。

- プラグイン隔離
- 動的ロードの破棄
- 部分信頼コードの隔離
- 一時的な実行環境の分離

移行前に見るべきなのは、**AppDomain という単語が出てくるか** だけではなく、**何のために AppDomain を使っていたか** です。

### 6.3 Remoting は「見た目より深い」

Remoting はもちろんですが、**delegate の `BeginInvoke()` / `EndInvoke()` 呼び出し** のような、Remoting 由来の振る舞いも影響範囲に入ることがあります。

なので、検索時には次も見ておくと安全です。

- `System.Runtime.Remoting`
- `MarshalByRefObject`
- `RealProxy`
- `BeginInvoke(` / `EndInvoke(`

### 6.4 BinaryFormatter は target version で突然前面化する

BinaryFormatter は、古いコードベースほど「自覚なく使っている」ことがあります。

- 永続化データ
- キャッシュ
- セッション保存
- プラグイン状態
- clipboard / drag & drop
- ResX
- WinForms / WPF デザイナーまわり

.NET 9 以降では、BinaryFormatter は runtime に実装が含まれず、API は **常に `PlatformNotSupportedException`** を投げます。  
つまり、これは「あとで考える」ではなく、**target version を決めた時点で先に監査する論点** です。

### 6.5 まず grep しておきたい検索語

着手前に、ソリューション全体へ次の語で検索をかけるだけでも景色がかなり変わります。

```text
System.Web
HttpContext.Current
System.Runtime.Remoting
MarshalByRefObject
AppDomain
BinaryFormatter
ServiceHost
ChannelFactory
System.EnterpriseServices
Workflow
packages.config
web.config.install.xdt
install.ps1
DllImport
AxInterop
Microsoft.Office.Interop
```

これらが 1 個でも見つかったら即アウト、という意味ではありません。  
**どこが標準ルートで移行できて、どこが別トラックになるかを知るための地図** です。

## 7. Windows 専用前提をどこまで許容するかを決める

移行でよく起きる誤解が、「.NET に移ったらクロスプラットフォームになる」というものです。  
そんな魔法はありません。アプリが Windows に深く結びついていれば、移行後も普通に Windows 専用です。

### 7.1 Windows 専用のまま移る、は十分に現実的

Microsoft には **Windows Compatibility Pack** があり、レジストリ、WMI、EventLog、Windows Service、Directory Services など、多くの Windows 系 API を modern .NET から使えるようにする手段があります。

これはかなり重要です。

- **まず modern .NET に移りたい**
- でも **当面 Windows からは出ない**
- だから **Windows API 依存は一旦許容したい**

という現場では、かなり有効です。

つまり、移行の最初の目標は必ずしも **クロスプラットフォーム化** でなくてよい、ということです。

### 7.2 ただし Windows 専用 API は「後で効いてくる借金」でもある

Windows Compatibility Pack があるからといって、何でも安心ではありません。

- Linux コンテナに載せたい
- Kubernetes 前提で動かしたい
- macOS / Linux 開発者も同じ build を回したい
- 将来クラウドで Windows VM を減らしたい

といった目標があるなら、**Windows API 依存は今のうちに可視化** しておいたほうがよいです。

### 7.3 `System.Drawing.Common` は特に誤解されやすい

`System.Drawing.Common` は、.NET 6 以降では **Windows 専用ライブラリ** です。  
つまり、画像処理や文字描画で使っているコードがあるなら、次を最初に決める必要があります。

- **Windows のまま運用するのか**
- **将来 Linux / macOS でも動かしたいのか**

前者なら当面そのままでもよいケースがあります。  
後者なら、SkiaSharp や ImageSharp などへの置き換えを、移行計画に最初から含める必要があります。

### 7.4 Windows 固定を示す代表的な匂い

次のような参照や API があるときは、「少なくとも最初は Windows 専用のまま移る」前提で見積もったほうが安全です。

- `Microsoft.Win32.Registry`
- `System.Management`
- `System.Diagnostics.EventLog`
- `System.ServiceProcess`
- `System.DirectoryServices`
- `System.Drawing`
- `DllImport` / P/Invoke
- COM 参照
- `AxInterop.*`
- `Microsoft.Office.Interop.*`

## 8. 共有ライブラリの切り出し方で難易度が変わる

大きめのソリューションでは、**移行の成否は shared library の切り方で決まる** と言っても大げさではありません。

### 8.1 まず分類する

ライブラリは大きく 3 種類に分けると整理しやすいです。

1. **純粋な業務ロジック / ドメインロジック**
2. **アプリモデルに少し依存する中間層**
3. **UI / Web / Windows API に密着した層**

このうち、一番先に移すべきなのは 1 です。

- 計算
- ルール判定
- DTO / 契約
- ドメインサービス
- 単純なデータ変換

ここがきれいに出せると、一気に難易度が下がります。

### 8.2 `netstandard2.0` は今でも有効な橋

Microsoft のガイダンスでは、**.NET Framework 側とも共存する必要がある shared library** なら、まず **`.NET Standard 2.0`** を考えるのが基本です。

ここで重要なのは 2 点です。

- **.NET Framework は `.NET Standard 2.1` をサポートしない**
- shared library を old / new 両方から参照したいなら、**2.0 が現実解** になりやすい

### 8.3 `netstandard2.0` にすると何が変わるか

| 方針 | どう変わるか | 向いているケース | 注意点 |
| --- | --- | --- | --- |
| `netstandard2.0` 化 | old / new 両方から参照しやすい | 純粋な業務ロジック、共通契約、ユーティリティ | app model 固有 API は載せられない |
| multi-target（例: `net48;net10.0`） | 共通コードを保ちつつ、環境別差分を持てる | 少しだけ環境差があるライブラリ | 条件分岐や build 管理が増える |
| いきなり `net10.0` 専用化 | 将来は最もきれい | old / new 共存が不要な新規層 | .NET Framework からは参照できない |

### 8.4 互換モードは万能ではない

.NET Standard 2.0 には、.NET Framework ライブラリを参照する互換モードがあります。  
ただし、これは **何でも透過的に動く魔法ではありません**。

たとえば、WPF のような app model 固有 API を前提にしたライブラリは普通に難しいです。  
つまり、**shared library と言っても、本当に shared できる責務だけへ絞る** のが重要です。

### 8.5 ASP.NET 系ライブラリは `System.Web` を剥がせるかが勝負

ASP.NET Framework を段階移行する場合、shared library が `HttpContext.Current` や `System.Web` に直接ぶら下がっていると、かなりつらいです。

このときの基本戦略は次のどれかです。

- `System.Web` 依存をインターフェースの外へ押し出す
- `HttpContext` 由来の情報を DTO として受け取るように変える
- 移行過渡期に adapter を使う
- それでも無理なら multi-target で段階的に剥がす

### 8.6 ライブラリは leaf-first で上げる

ASP.NET の incremental migration ガイドでは、supporting library を **postorder depth-first**、つまり **葉から順に** 上げることが明示されています。

これは Web に限らず、一般のソリューションでもかなり有効です。

- 依存先が先に上がっているので、上位層の見通しが良くなる
- 互換性問題を局所化しやすい
- ライブラリ単位でテストしやすい

## 9. NuGet / 外部依存 / サードパーティ部品を棚卸しする

ここを雑にやると、移行の後半で一番痛い目を見ます。

### 9.1 依存関係は 4 種類に分けると整理しやすい

1. **公開 NuGet パッケージ**
2. **社内 private package / internal library**
3. **ローカル DLL 参照**
4. **COM / ActiveX / ネイティブ DLL / SDK**

このうち 1 だけ見ても足りません。  
本当に危ないのは 3 と 4 です。

### 9.2 依存ごとに確認したいこと

各依存について、最低でも次を見ます。

- modern .NET をターゲットにしているか
- `PackageReference` に対応しているか
- SDK スタイルで問題ないか
- x86 / x64 / ARM64 の制約はないか
- 設計時ツールや Visual Studio 拡張に依存していないか
- install script / config transform を前提にしていないか
- サポートが継続しているか

### 9.3 サードパーティ UI / レポート / 設計時部品は別枠で見積もる

WinForms / WPF / ASP.NET の移行では、ここがかなり効きます。

- グリッド
- レポートエンジン
- PDF 出力部品
- グラフ部品
- デザイナー統合型の UI ライブラリ
- ActiveX ラッパー

これらは **runtime だけでなく設計時サポート** が絡みます。  
移行の見積もりで「コンパイルできるか」だけを見ると、普通に外します。

### 9.4 ネイティブ DLL と bitness は必ず見る

.NET Framework 時代に `AnyCPU` で動いていたように見えても、実際には次へ依存していることがあります。

- `x86` 固定の COM
- 32bit 専用 ActiveX
- 特定バージョンの VC++ Runtime
- 署名済みネイティブ DLL

このあたりは modern .NET 化で突然生えてきた問題ではなく、**元からあった制約が表面化する** だけです。  
だからこそ、移行前に可視化しておく価値があります。

## 10. EF6、シリアライザー、データまわりを別問題として扱う

runtime の移行と、データアクセスやシリアライズの再設計は、**なるべく別問題として扱ったほうがうまくいきます。**

### 10.1 EF6 → EF Core は直接アップグレードではない

Microsoft の EF ガイドでも、**EF Core は EF6 の total rewrite であり、direct upgrade path はない** とされています。

なので、EF6 を使っているアプリでは次の順番が現実的です。

1. まず modern .NET に移る
2. **必要なら EF6 を維持したまま** アプリを動かす
3. その後で EF Core へ別プロジェクトとして移行する

これはかなり重要です。  
**runtime migration と ORM migration を一緒にしない** だけで、難易度はかなり下がります。

### 10.2 EF6 を残すと何が変わるか

- **良い点**
  - データアクセス層の差分を後回しにできる
  - business logic や app model の移行に集中できる
  - 「EF Core の振る舞い差」が混ざらない
- **注意点**
  - 新規開発の観点では EF Core が本命
  - EF6 Designer / EDMX 利用形態には別の制約がある

### 10.3 EDMX ベースの EF6 は「設計時」まで見る

EF6 のドキュメントには、**EF Designer は .NET / .NET Standard プロジェクトや SDK スタイルの .NET Framework プロジェクトで直接サポートされない** と書かれています。

つまり、EDMX ベースのアプリでは次を分けて考える必要があります。

- 実行時に動くか
- Designer が使えるか
- 生成コードの扱いをどうするか

EDMX を多用しているなら、これは最初に見積もりへ入れておいたほうが安全です。

### 10.4 BinaryFormatter や独自シリアライズは「隠れ依存」になりやすい

シリアライザーはコード検索だけでは見落としやすいです。

- 永続化フォーマット
- メッセージング
- キャッシュ
- 旧 WCF / SOAP 契約
- ResX
- クリップボード / drag & drop

このあたりは **データの互換性** も絡みます。  
つまり、単に「ビルドできたか」ではなく、**古いデータを読めるか** まで確認が必要です。

## 11. 構成、配布、運用、CI/CD まで移行対象に含める

移行の対象はソースコードだけではありません。

### 11.1 設定ファイル

.NET Framework 側では `app.config` / `web.config` にかなりのものが乗っていることがあります。

- connection string
- custom config section
- WCF endpoint 設定
- binding redirect
- diagnostics
- ASP.NET の各種設定
- package install 時の transform 結果

modern .NET 側では、構成の持ち方や読み込み経路が変わる場面があります。  
なので「設定ファイルは後で」は危険です。

最初にやることは、**設定の棚卸し** です。

- 何が設定ファイルにあるのか
- どれがアプリ起動時に必須か
- どれが環境差分か
- どれが NuGet や installer により自動注入されていたか

### 11.2 配布方式

次も確認しておきたいところです。

- IIS 配下か
- Windows Service か
- Scheduled Task か
- ClickOnce / MSI / 独自 installer か
- オンプレサーバー前提か
- self-contained / framework-dependent のどちらが向くか

実行本体が移行できても、**配布と起動の仕組みが古い前提のまま** だと最後に詰まります。

### 11.3 ログ、監視、運用手順

運用まわりも見落としやすいです。

- Windows Event Log 前提か
- Performance Counter を見ているか
- WMI ベースの監視か
- サービスアカウントや権限が固定か
- ログの出力先がローカルファイル前提か

移行後にコードは動いても、**運用が回らない** というのは普通にあります。

### 11.4 CI/CD と build agent

移行前に、次も確認します。

- build agent に必要な .NET SDK が入るか
- `nuget.exe` / `msbuild.exe` 前提の pipeline をどうするか
- `dotnet` CLI ベースに寄せるのか
- テスト実行、coverage、publish のジョブをどう更新するか
- 社内テンプレートや reusable pipeline が古い形式前提ではないか

**人のローカル環境では動くのに CI が死ぬ** は、移行あるあるです。

## 12. 現実的な移行の進め方

ここまでの論点を踏まえると、現実的な進め方はだいたい次の形に落ちます。

### 12.1 まず現行 Framework 側を整える

1. .NET Framework 4.7.2 以降、できれば 4.8.1 に寄せる
2. 依存関係を上げる
3. `packages.config` を見直す
4. 可能な範囲で `PackageReference` と SDK スタイルに寄せる
5. 現行アプリがその状態でちゃんと動くことを確認する

ここをやるだけで、後段の差分がだいぶ減ります。

### 12.2 shared library を先に救出する

次に、業務ロジックや共通契約を `netstandard2.0` または multi-target に寄せます。  
上げる順番は、**leaf-first** が基本です。

### 12.3 アプリ本体は app model ごとに戦略を変える

- **クラスライブラリ / コンソール / 一部サービス**  
  比較的ストレートに進めやすい
- **WinForms / WPF**  
  Windows 専用のまま modern 化する
- **ASP.NET MVC / Web API**  
  小さければ一括、重ければ段階移行
- **Web Forms**  
  画面資産の置換を前提に、shared logic を先に逃がす
- **WCF サーバー**  
  CoreWCF 維持か gRPC 再設計か先に決める

### 12.4 「一度に全部やらない」を守る

特に避けたい組み合わせは次です。

- runtime 移行 + ORM 総入れ替え
- runtime 移行 + 認証基盤変更
- runtime 移行 + クラウド全面移行
- runtime 移行 + 監視基盤変更
- runtime 移行 + UI フレームワーク刷新

全部必要でも、**同じスプリントに積まない** ほうが大抵はうまくいきます。

### 12.5 テストとベースラインを取ってから動く

最低でも、次はほしいところです。

- 単体テスト
- 主要業務フローの結合テスト
- 代表的な画面 / API のスナップショット的確認
- 性能ベースライン
- 主要ログの確認方法
- ロールバック手順

移行後の「何が壊れたか」を特定できない状態で進めるのは、かなり危険です。

## 13. 着手前チェックリスト

そのままプロジェクト管理に貼れる形で置いておきます。

### 13.1 方針

- [ ] なぜ移行するのかを 1 文で言える
- [ ] 今回の着地点が **Windows 専用の modern .NET** なのか、**将来のクロスプラットフォーム化** なのか決まっている
- [ ] target の .NET バージョンを決めた
- [ ] 今回のスコープに **含めないもの**（EF Core 化、認証刷新、クラウド全面移行など）が決まっている

### 13.2 現行 .NET Framework 側の整備

- [ ] .NET Framework 4.7.2 以降、できれば 4.8.1 に寄せた
- [ ] 依存関係を最新寄りへ上げた
- [ ] `packages.config` の有無を洗った
- [ ] `PackageReference` 化の可否を確認した
- [ ] SDK スタイル化の可否を確認した
- [ ] 現行アプリがその状態でビルド・起動・テストできる

### 13.3 アプリ種別と技術選定

- [ ] クラスライブラリ / デスクトップ / Web / WCF などの種別ごとに難易度を分けた
- [ ] WinForms / WPF が Windows 専用のままだと理解している
- [ ] ASP.NET Framework は ASP.NET Core への app model 移行だと理解している
- [ ] Web Forms の UI 層置換を見積もりに入れた
- [ ] WCF はクライアントとサーバーを分けて評価した

### 13.4 非対応技術・要注意 API

- [ ] `AppDomain` 依存を洗った
- [ ] Remoting / `MarshalByRefObject` / `BeginInvoke` / `EndInvoke` を洗った
- [ ] CAS / Security Transparency / COM+ / WF を洗った
- [ ] BinaryFormatter 依存を洗った
- [ ] `System.Web` 依存を洗った

### 13.5 Windows 専用依存

- [ ] レジストリ、WMI、EventLog、Windows Service、Directory Services の利用を洗った
- [ ] `System.Drawing.Common` の利用を洗った
- [ ] COM / ActiveX / Office Interop / P/Invoke / ネイティブ DLL を洗った
- [ ] x86 / x64 / ARM64 の制約を確認した

### 13.6 shared library とデータアクセス

- [ ] shared library を **業務ロジック / app model 密着層** に分類した
- [ ] `netstandard2.0` 化できるものを洗った
- [ ] multi-target が必要なライブラリを洗った
- [ ] EF6 を残して runtime だけ先に移せるか判断した
- [ ] EDMX / Designer 依存を確認した

### 13.7 運用と build

- [ ] 設定ファイルの棚卸しをした
- [ ] 配布方式（IIS / Service / MSI / ClickOnce など）を確認した
- [ ] ログ / 監視 / 権限 / 実行アカウント前提を確認した
- [ ] CI/CD と build agent の更新が必要か確認した
- [ ] ロールバック手順を作った

## 14. まとめ

.NET Framework から .NET への移行で大事なのは、「どのコマンドで移すか」よりも **何がそのまま行けて、何が別問題なのかを着手前に見抜くこと** です。

特に押さえておきたいのは次です。

- **移行前に .NET Framework 側を整理する**
- **アプリモデルごとに難易度を分ける**
- **使えない技術を先に洗う**
- **Windows 専用前提をどこまで許容するかを決める**
- **shared library をどう切るか決める**
- **ORM、認証、クラウド移行を同時に盛りすぎない**

移行は、最初の 1 週間で見積もりの精度がかなり変わります。  
逆に言えば、その 1 週間で論点を整理できれば、後半はかなり普通の開発に寄せられます。

「まず `net10.0` に変えてみよう」は、探索としては悪くありません。  
ただし本番移行としては、**その前に見るべきところがある**。この記事で整理したのは、まさにそこです。

## 15. 参考資料

- [コードを移植するための前提条件](https://learn.microsoft.com/ja-jp/dotnet/core/porting/premigration-needed-changes)
- [.NET Framework から .NET への移植の概要](https://learn.microsoft.com/ja-jp/dotnet/core/porting/framework-overview)
- [.NET 6 以降では使用できない .NET Framework テクノロジ](https://learn.microsoft.com/ja-jp/dotnet/core/porting/net-framework-tech-unavailable)
- [GitHub Copilot モダン化とは](https://learn.microsoft.com/ja-jp/dotnet/core/porting/github-copilot-app-modernization/overview)
- [GitHub Copilot モダン化のインストール](https://learn.microsoft.com/ja-jp/dotnet/core/porting/github-copilot-app-modernization/install)
- [公式の .NET サポート ポリシー](https://dotnet.microsoft.com/ja-jp/platform/support/policy/dotnet-core)
- [.NET Framework 公式サポート ポリシー](https://dotnet.microsoft.com/ja-jp/platform/support/policy/dotnet-framework)
- [ツールを使用して ASP.NET Framework を ASP.NET Core に移行する](https://learn.microsoft.com/ja-jp/aspnet/core/migration/fx-to-core/tooling?view=aspnetcore-10.0)
- [ASP.NET Framework から ASP.NET Core への移行](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/?view=aspnetcore-10.0)
- [Get started with incremental ASP.NET to ASP.NET Core migration](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/start?view=aspnetcore-10.0)
- [Use the Windows Compatibility Pack to port code to .NET](https://learn.microsoft.com/en-us/dotnet/core/porting/windows-compat-pack)
- [.NET Standard](https://learn.microsoft.com/en-us/dotnet/standard/net-standard)
- [Cross-platform targeting for .NET libraries](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/cross-platform-targeting)
- [packages.config から PackageReference に移行する](https://learn.microsoft.com/ja-jp/nuget/consume-packages/migrate-packages-config-to-package-reference)
- [PackageReference in project files](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files)
- [BinaryFormatter migration guide](https://learn.microsoft.com/ja-jp/dotnet/standard/serialization/binaryformatter-migration-guide/)
- [Windows Forms のための BinaryFormatter 移行ガイド](https://learn.microsoft.com/ja-jp/dotnet/standard/serialization/binaryformatter-migration-guide/winforms-applications)
- [WCF Client Support Policy](https://dotnet.microsoft.com/ja-jp/platform/support/policy/wcf-client)
- [CoreWCF Support Policy](https://dotnet.microsoft.com/en-us/platform/support/policy/corewcf)
- [Why migrate WCF to ASP.NET Core gRPC](https://learn.microsoft.com/en-us/aspnet/core/grpc/why-migrate-wcf-to-dotnet-grpc?view=aspnetcore-10.0)
- [Port from EF6 to EF Core](https://learn.microsoft.com/en-us/ef/efcore-and-ef6/porting/)
- [EF6 の新機能](https://learn.microsoft.com/ja-jp/ef/ef6/what-is-new/)
