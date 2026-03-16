# .NET における Native AOT とは何か - JIT、ReadyToRun、trimming との違いを先に整理

2026年03月13日 10:00 · Go Komura · C#, .NET, Native AOT, 発行, 設計

すでに [C# を Native AOT でネイティブ DLL にする方法 - UnmanagedCallersOnly で C/C++ から呼び出す](https://comcomponent.com/blog/2026/03/12/003-csharp-native-aot-native-dll-from-c-cpp/) では、Native AOT を使って C/C++ から C# を呼ぶ話を書きました。  
ただ、順番としては、その前に **そもそも Native AOT とは何か** を置いたほうが親切でした。少しだけ順番が前後しています。

Native AOT の話は、最初に用語がかなり混ざりやすいです。

- JIT をなくす話なのか
- self-contained や single-file と何が違うのか
- ReadyToRun と同じ系統なのか
- trimming warning が大量に出るのは何が起きているのか
- WPF / WinForms / ASP.NET Core でも同じ温度感で使えるのか

このへんが一緒くたになると、Native AOT が「ただ速くなる魔法」に見えたり、逆に「制約だらけで怖いもの」に見えたりします。どちらも少し雑です。

この記事では、主に .NET 8 以降の現在の実務感を前提に、次の 4 つを先に整理します。

- Native AOT の正体
- 何がうれしくて、どこが厳しくなるのか
- ReadyToRun や trimming とどう違うのか
- どんなアプリから試すと穏やかか

## 目次
1. まず結論（ひとことで）
2. まず見る整理表
   * 2.1. Native AOT まわりの言葉
   * 2.2. JIT / ReadyToRun / Native AOT の違い
3. Native AOT の全体像（図）
4. Native AOT で何がうれしいか
   * 4.1. 起動が軽くなりやすい
   * 4.2. ランタイム事前インストールを前提にしなくてよい
   * 4.3. 制限のある実行環境に向く
5. Native AOT で何が厳しくなるか
   * 5.1. リフレクションと動的コード生成
   * 5.2. trimming 前提で考える必要がある
   * 5.3. プラットフォームごとに発行する
   * 5.4. Windows デスクトップ / COM 文脈はかなり慎重
6. 最小手順
   * 6.1. `csproj`
   * 6.2. publish
   * 6.3. JSON の書き方
7. 向いているケース
8. 向かないケース
9. はまりどころ
10. まとめ
11. 参考資料

* * *

## 1. まず結論（ひとことで）

- Native AOT は、.NET アプリを publish 時にネイティブコードへ事前コンパイルして配布する方式です。
- 実行時 JIT を使わないので、起動時間とメモリ占有が良くなりやすく、.NET ランタイム未インストール環境にも配りやすいです。
- ただし、自由なリフレクション、動的コード生成、built-in COM、trimming 非対応ライブラリとは相性が悪くなります。
- つまり、速くなる魔法というより、起動・配布・実行環境の都合のために、動的な世界を少し捨てて静的な世界へ寄せる 発行モデルです。

要するに、Native AOT は「.NET をネイティブっぽく配るための仕組み」であって、単なるコンパイル高速化のチェックボックスではありません。

## 2. まず見る整理表

### 2.1. Native AOT まわりの言葉

最初に、このへんを分けておくとかなり楽です。

| 用語 | 何をするものか | Native AOT との関係 |
| --- | --- | --- |
| JIT | 実行時に IL からネイティブコードを作る | Native AOT はここを事前に済ませる |
| self-contained | 実行に必要な .NET 一式も一緒に配る | Native AOT はこの系統で考える |
| single-file | 配布物を 1 ファイルにまとめる | Native AOT の本質とは別ですが、結果の見た目は近くなりやすい |
| trimming | 使っていないコードを削る | Native AOT ではほぼ前提になる |
| ReadyToRun | IL を残したまま、JIT の仕事を少し前倒しする | Native AOT とは似て非なる別物 |
| source generator | 実行時の動的処理を、ビルド時コード生成へ寄せる | Native AOT と相性がよい |

混ざりやすいのは、Native AOT が 1 個の機能というより、self-contained、trimming、source generation、RID 固定 publish などと仲良く動く 発行モデル であることです。

### 2.2. JIT / ReadyToRun / Native AOT の違い

ここも最初に 1 枚で見たほうが早いです。

| 観点 | ふつうの JIT 実行 | ReadyToRun | Native AOT |
| --- | --- | --- | --- |
| 実行時 JIT | 使う | まだ使う場面がある | 使わない |
| 配布物の中身 | IL 中心 | IL + 事前生成コード | ネイティブ実行ファイル中心 |
| 起動 | 基準 | 改善しやすい | かなり改善しやすい |
| 互換性 | いちばん広い | 広い | 制約が強い |
| 動的機能 | 使いやすい | だいたい使いやすい | 制限が多い |
| 向いている目的 | ふつうの .NET 開発全般 | まずは起動改善したい | 起動・配布・制限環境を強く取りにいく |

ReadyToRun は、「JIT を少し楽にする」方向です。  
一方の Native AOT は、「実行時 JIT 自体を前提にしない」方向です。  
同じ AOT という言葉が付いていても、温度感はかなり違います。

## 3. Native AOT の全体像（図）

Native AOT をざっくり図にすると、こうです。

```mermaid
flowchart LR
    Src["C# / .NET ソースコード"] --> IL["IL アセンブリ"]
    IL -->|通常実行| JIT["実行時 JIT"]
    JIT --> Run1["アプリ実行"]

    IL -->|dotnet publish + PublishAot| Analyze["AOT / trim 解析"]
    Analyze --> Trim["不要コードの削減"]
    Trim --> AOT["ネイティブコード生成"]
    AOT --> Run2["RID 固有の実行ファイル"]
```

普段の .NET は、まず IL を作って、実行時に必要な分だけ JIT します。  
Native AOT は、その後段のかなり大きな部分を publish 時に前倒しします。

このとき大事なのは、publish 時点で「実行時に必要になるコードを、ほぼ全部知っている必要がある」ことです。  
ここで空気が変わります。

- 実行時に型を見つける
- 実行時にコードを生やす
- 実行時に Assembly を読み込む
- 実行時に「まあ何とかなるでしょう」で遅延解決する

こういう書き方は、Native AOT と急に相性が悪くなります。

## 4. Native AOT で何がうれしいか

### 4.1. 起動が軽くなりやすい

Native AOT のいちばん分かりやすい効き目は、やはり起動です。

- CLI ツール
- 短命プロセス
- サーバーレスっぽい起動
- コンテナの起動・入れ替え
- 監視ツールや小さな常駐プロセス

このへんでは、JIT コストが見えやすいです。  
Native AOT はそこをかなり前倒しできるので、初動が軽くなりやすいです。

また、メモリ占有も良くなりやすいので、同じ台数を詰め込みたい場面ではかなり効きます。  
特に、同じプロセスが大量に立つクラウド側では、この差がじわじわ効きます。

### 4.2. ランタイム事前インストールを前提にしなくてよい

Native AOT で publish したアプリは、.NET ランタイム未インストール環境でも動かしやすくなります。

これは地味に大きいです。

- 配布先に「.NET 9 Runtime を先に入れてください」と言いたくない
- コンテナイメージを細くしたい
- 小さいツールを 1 本だけ置いて動かしたい
- 実行環境に JIT を許したくない / 許されない

こういう場面では、「ランタイムを別途そろえる前提」がないだけで、かなり話が静かになります。

ここでいう「ランタイム不要」は、配布先に別途 .NET を入れなくてよい という意味です。  
アプリの中に必要な runtime 相当部分まで完全に消える、という話ではありません。

### 4.3. 制限のある実行環境に向く

Native AOT は、実行時 JIT を使わないので、JIT が許されない環境でも動かしやすいです。

ここは desktop よりも、クラウド、コンテナ、モバイル寄りの話で効きやすいです。  
ただ、Windows 開発の文脈でも、「配布先で余計な前提を減らしたい」という意味では十分うれしい点です。

## 5. Native AOT で何が厳しくなるか

### 5.1. リフレクションと動的コード生成

Native AOT の本丸の制約はここです。

- `Assembly.LoadFile` のような動的読み込み
- `System.Reflection.Emit` のような実行時コード生成
- 実行時に無制限に型をたどるリフレクション
- 実行時に generic を好き放題組み立てるような書き方

このへんは、publish 時に必要コードを確定しにくいので、AOT warning の温床になります。

もちろん、リフレクションが 1 行でもあれば即アウト、というほど単純ではありません。  
ただ、**「実行時に見て決める」寄りの設計ほど厳しくなる** のはかなり本質です。

warning 名でよく出てくるのは `RequiresDynamicCode` 系です。  
これは「その呼び出しは AOT で壊れるかもしれない」という意味なので、雑に suppress しないほうが安全です。

Native AOT をやるときは、「実行時の賢さ」を減らして、「ビルド時の明示」を増やす方向へ寄せる、と思っておくと分かりやすいです。

### 5.2. trimming 前提で考える必要がある

Native AOT は trimming とかなり深く結びつきます。  
ここで見落としやすいのが、**自分のコードだけでなく、依存ライブラリ側の書き方も効く** ことです。

たとえば次のようなものは要注意です。

- reflection ベースのシリアライザー
- 実行時スキャンで型を集める DI / プラグイン構成
- 文字列名から型を探して実体化する仕組み
- 動的 proxy や IL 生成に寄るライブラリ

ここで warning が出ているのに「publish は通ったからヨシ」とすると、あとでかなり渋いです。  
Native AOT では、warning はだいたい本気で読んだほうがよいです。

### 5.3. プラットフォームごとに発行する

Native AOT は RID（Runtime Identifier）固定で publish します。  
つまり、`win-x64` 用に作ったものを、そのまま `linux-x64` で動かす、という世界ではありません。

- Windows x64
- Windows Arm64
- Linux x64
- Linux Arm64
- macOS Arm64

のように、ターゲットごとに発行物を作る前提です。

ここは、ふつうの framework-dependent な .NET より、かなり「ネイティブアプリっぽい」感覚になります。

### 5.4. Windows デスクトップ / COM 文脈はかなり慎重

KomuraSoft の文脈だと、ここはかなり重要です。

Windows では Native AOT に built-in COM がありません。  
さらに、WPF は trimming と相性が悪く、WinForms は built-in COM marshalling への依存が重いため、少なくとも現時点では、どちらも「最初の Native AOT 候補」としてはかなり慎重に見たほうがよいです。

要するに、

- WPF / WinForms 本体をいきなり Native AOT 化する
- COM interop を普通の感覚でそのまま持ち込む

このへんは、かなり空気が重くなりやすいです。

逆に、

- コンソール
- worker
- 小さな Web API
- ネイティブ連携の中でも C の関数境界に寄せやすい部品

のほうが入り口として素直です。

COM が必要なら、JIT のままにするか、`ComWrappers` / source-generated COM を前提に設計し直すほうが筋がよい場面もあります。

## 6. 最小手順

### 6.1. `csproj`

まずはプロジェクトファイルに `PublishAot` を入れます。

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <PublishAot>true</PublishAot>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
```

サンプルは `net8.0` で十分です。考え方自体は .NET 9 / 10 でもほぼ同じです。

大事なのは、`dotnet publish` のコマンドラインにだけ一時的に付けるより、  
**ふだんからプロジェクトに置いて、build / publish 時の解析を日常的に見る** ことです。

なお、`<PublishAot>true</PublishAot>` を入れても、普段のローカル実行までいきなり Native AOT になるわけではありません。  
日常の `dotnet run` や通常実行は JIT で、Native AOT コンパイルの本番は publish 時です。

### 6.2. publish

たとえば Windows x64 向けなら、こんな形です。

```bash
dotnet publish -c Release -r win-x64
```

Linux x64 向けなら、こうです。

```bash
dotnet publish -c Release -r linux-x64
```

出力は RID 固定です。  
「1 本でどこでも動く .NET DLL」より、「その OS / アーキテクチャ向けに作った実行ファイル」という見方に変わります。

Web API 側から触るなら、Native AOT 前提のテンプレートから入るとかなり楽です。

```bash
dotnet new webapiaot -o MyFirstAotWebApi
```

worker なら、こちらです。

```bash
dotnet new worker -o WorkerWithAot --aot
```

### 6.3. JSON の書き方

Native AOT で地味によく当たるのが JSON です。  
`System.Text.Json` は普段の感覚で使うと reflection へ寄りやすいので、source generation に寄せたほうが穏やかです。

```csharp
using System.Text.Json;
using System.Text.Json.Serialization;

[JsonSerializable(typeof(AppConfig))]
internal partial class AppJsonContext : JsonSerializerContext
{
}

public sealed class AppConfig
{
    public string? Name { get; init; }
    public int RetryCount { get; init; }
}

var config = new AppConfig
{
    Name = "sample",
    RetryCount = 3
};

string json = JsonSerializer.Serialize(config, AppJsonContext.Default.AppConfig);
```

実務では、Native AOT 対応というより、**「実行時に型を探させない」方向へ寄せる** と覚えておくと外しにくいです。

## 7. 向いているケース

Native AOT が気持ちよくハマりやすいのは、たとえば次です。

- 起動が主役の CLI / ツール
- コンテナで大量配備する小さな API
- worker / バックグラウンドサービス
- サーバーレスや短命プロセス
- ネイティブアプリに差し込む小さな .NET 部品
- 実行環境に .NET ランタイムの事前インストールを求めたくない場面

共通しているのは、**境界が比較的はっきりしていて、動的な仕組みを減らしやすい** ことです。

## 8. 向かないケース

逆に、最初から Native AOT を主戦場にしないほうがよい場面もはっきりあります。

- WPF / WinForms の既存大規模アプリ本体
- built-in COM interop 前提の構成
- 実行時 plugin 読み込みが主役のアプリ
- reflection で型探索するフレームワーク依存が強い構成
- `System.Reflection.Emit` や動的 proxy を当然のように使うライブラリ
- C++/CLI を挟んだ設計

このへんは、JIT 前提のふつうの .NET、あるいは ReadyToRun、あるいは設計の切り分け見直しのほうが筋がよいです。

## 9. はまりどころ

最後に、Native AOT 初手で踏みやすい点をまとめます。

- **publish warning を軽く見る**
  - Native AOT では、warning はかなり重要です。
- **build は通るのに publish で壊れる**
  - publish 時に依存ライブラリまで含めた解析が本気で走るので、ここで初めて見えるものがあります。
- **ReadyToRun と Native AOT を同じ気分で扱う**
  - 似た言葉ですが、制約の強さがかなり違います。
- **desktop アプリ本体からいきなり始める**
  - まずは console / worker / 小さな API のほうが穏やかです。
- **JSON や設定バインドを普段のノリで書く**
  - reflection 前提の書き方は、あとで効いてきます。
- **プラットフォーム非依存のつもりで配る**
  - Native AOT の配布物は RID 固定です。
- **「Native AOT = なんでも速くなる」と思う**
  - 主役は起動、配布、実行環境です。ここを外すと期待値がずれます。

Native AOT では、**`dotnet build` より `dotnet publish` のほうが審判っぽい** です。  
ここを早めに回し始めると、後半で困りにくくなります。

## 10. まとめ

Native AOT をひとことで言うと、  
**.NET アプリを、動的な実行モデルから、静的に確定しやすい配布モデルへ寄せる仕組み** です。

見ておきたいポイントをもう一度まとめると、次です。

1. Native AOT は publish 時にネイティブコードへ事前コンパイルする
2. 起動、メモリ、配布の都合にはかなり効く
3. その代わり、reflection、動的コード生成、built-in COM、trimming 非対応コードには厳しい
4. 最初の対象は、desktop 本体より console / worker / 小さな API のほうが穏やか
5. warning を消しながら、publish ベースで早めに確かめるのが大事

Native AOT は、全部の .NET アプリに付ける標準スイッチではありません。  
ですが、**起動が大事、配布を軽くしたい、実行環境の前提を減らしたい** という場面では、かなり強い武器です。

逆に、WPF / WinForms / COM の濃い世界では、まだ普通の .NET のほうが筋がよい場面も多いです。  
ここを見分けられると、Native AOT は「難しい新機能」ではなく、使いどころのはっきりした選択肢 になります。

## 11. 参考資料

- [Native AOT deployment overview - .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [Native AOT deployment overview - .NET (日本語)](https://learn.microsoft.com/ja-jp/dotnet/core/deploying/native-aot/)
- [Introduction to AOT warnings - .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/fixing-warnings)
- [Prepare .NET libraries for trimming - .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/prepare-libraries-for-trimming)
- [Known trimming incompatibilities - .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/incompatibilities)
- [How to use source generation in System.Text.Json - .NET](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation)
- [ASP.NET Core support for Native AOT](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/native-aot?view=aspnetcore-10.0)
- [ReadyToRun deployment overview - .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/ready-to-run)
- [Building native libraries - .NET](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/libraries)
- [ComWrappers source generation - .NET](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/comwrappers-source-generation)
- [関連記事: C# を Native AOT でネイティブ DLL にする方法 - UnmanagedCallersOnly で C/C++ から呼び出す](https://comcomponent.com/blog/2026/03/12/003-csharp-native-aot-native-dll-from-c-cpp/)
- [関連記事: C# からネイティブ DLL を使うなら C++/CLI ラッパーが有力な理由 - P/Invoke と比較して整理](https://comcomponent.com/blog/2026/03/07/000-cpp-cli-wrapper-for-native-dlls/)
