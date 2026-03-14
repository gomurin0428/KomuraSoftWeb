---
title: ".NET における Native AOT とは何か - JIT、ReadyToRun、trimming との違いを先に整理"
date: 2026-03-13 10:00
lang: ja
translation_key: dotnet-native-aot-what-is
tags:
  - C#
  - .NET
  - Native AOT
  - 発行
  - 設計
description: "Native AOT とは何かを、JIT、ReadyToRun、self-contained、single-file、trimming、source generator との違いから整理し、向いているケースと厳しいケースを実務目線でまとめます。"
---

前に [C# を Native AOT でネイティブ DLL にする方法 - UnmanagedCallersOnly で C/C++ から呼び出す](https://comcomponent.com/blog/2026/03/12/003-csharp-native-aot-native-dll-from-c-cpp/) を書いたのですが、あれは少し順番が逆でした。  
本当は、その前に「そもそも Native AOT って何なのか」を置くほうが自然でした。

Native AOT の話は、最初にこのあたりが混ざりやすいです。

- JIT を消す話なのか
- self-contained や single-file と何が違うのか
- ReadyToRun と同じ系統なのか
- trimming warning が大量に出るのは何が起きているのか
- WPF や WinForms でもそのまま乗れるのか

このへんが混ざったままだと、Native AOT が「ただ速くなる魔法」に見えたり、逆に「制約だらけで触ってはいけないもの」に見えたりします。  
どちらも少し雑です。

Native AOT は、ひとことで言えば **.NET アプリを publish 時点でかなり静的に固める発行モデル** です。  
その代わり、起動や配布の都合にはよく効きます。  
逆に、実行時にあれこれ動的に解決したいコードとは相性が落ちます。

この記事では、そこを実務寄りに整理します。

## 1. Native AOT は何をしているのか

普段の .NET は、まず IL を作って、実行時に必要なところを JIT します。  
Native AOT は、その「実行時にネイティブコードを作る」部分を publish 時にかなり前倒しします。

なので、見た目としては「.NET をネイティブアプリっぽく配る」方向です。

ここで大事なのは、**publish 時に必要なコードがかなり見えていてほしい** という点です。

つまり、

- 実行時に型を探す
- 実行時にコードを生やす
- 実行時にアセンブリを読んで判断する

みたいな書き方とは、どうしても相性が悪くなります。

Native AOT を「速くなる機能」とだけ見るとここで外します。  
本質はむしろ、**動的な世界を少し捨てて、静的に固めやすい世界へ寄せる** ことです。

## 2. ReadyToRun と何が違うのか

ここは最初に分けておくとかなり楽です。

| 観点 | ふつうの JIT | ReadyToRun | Native AOT |
| --- | --- | --- | --- |
| 実行時 JIT | 使う | まだ使う | 使わない |
| 配布物 | IL 中心 | IL + 事前生成コード | ネイティブ実行ファイル中心 |
| 起動 | 基準 | 改善しやすい | さらに改善しやすい |
| 互換性 | 広い | 比較的広い | 制約が強い |

ReadyToRun は、JIT の仕事を少し前倒しする方向です。  
一方の Native AOT は、**実行時 JIT を前提にしない** 方向です。

似た言葉ですが、実際の手触りはけっこう違います。  
ReadyToRun は「まず起動を少し楽にしたい」。  
Native AOT は「起動、配布、実行環境の都合のために、設計も少し静的寄りにする」です。

## 3. Native AOT で何がうれしいのか

いちばん分かりやすいのはやはり起動です。

CLI ツールや短命プロセス、コンテナの小さな API、常駐はするけれど機能が絞られているツールでは、JIT の重さが見えやすいです。  
Native AOT はそこを先に済ませるので、初動が軽くなりやすいです。

もうひとつは、配布の話です。  
「配布先に .NET Runtime を先に入れてください」と言いたくない場面では、だいぶ気持ちが楽になります。

- 小さなツールを 1 本だけ配りたい
- コンテナイメージをできるだけ軽くしたい
- 実行環境に JIT を置きたくない

こういうとき、Native AOT は使いどころがはっきりしています。

なので、Native AOT が刺さる場面は「全部のアプリ」ではなく、**起動、配布、実行環境の前提を減らしたいアプリ** です。

## 4. 逆に何が厳しくなるのか

ここはかなりはっきりしています。  
まず、リフレクションや動的コード生成です。

- `Assembly.LoadFile`
- `System.Reflection.Emit`
- 実行時に型を列挙して探す構成
- 文字列名から型を引いて実体化する仕組み

このへんは、publish 時に必要コードを確定しづらいので、AOT warning の温床になります。

Native AOT で warning がたくさん出るとき、「うるさいな」ではなく「その設計は publish 時に見えにくいんだな」と読むほうが本質に近いです。  
特に `RequiresDynamicCode` 系は、だいたい真面目に見たほうがいいです。

次に trimming です。  
Native AOT は trimming とかなり深く結びつきます。  
ここで厄介なのは、自分のコードだけでなく、依存ライブラリの書き方まで効くことです。

たとえば、

- reflection ベースのシリアライザー
- 実行時スキャン前提の DI
- 動的 proxy を使うライブラリ

このへんは面倒になりやすいです。

つまり、Native AOT をやるときは「実行時に賢く何とかする」より、**ビルド時に分かる形へ寄せる** ほうが扱いやすいです。

## 5. Windows デスクトップでは少し慎重に見たほうがいい

Windows では Native AOT に built-in COM がありません。  
さらに、WPF は trimming と相性がよくなく、WinForms も built-in COM marshalling への依存が重いです。

なので、

- WPF / WinForms の本体をいきなり Native AOT 化する
- COM interop を普通の感覚のまま持ち込む

このへんは、慎重に見たほうがいいです。

逆に、入り口として選びやすいのは、

- コンソール
- worker
- 小さな Web API
- 境界がはっきりした小さな部品

です。

Native AOT は「.NET なら何でもそのまま乗る」感じではありません。  
特に Windows デスクトップと COM の濃い世界では、まだ JIT のままのほうが筋がいい場面も多いです。

## 6. 最小手順はシンプル

プロジェクト側では、まず `csproj` に `PublishAot` を入れます。

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

publish は、たとえば Windows x64 ならこうです。

```bash
dotnet publish -c Release -r win-x64
```

Linux x64 なら、

```bash
dotnet publish -c Release -r linux-x64
```

この時点で、もうかなり「ネイティブアプリっぽい世界」です。  
RID 固定なので、1 本でどこでも動く DLL というより、その OS / アーキテクチャ向けに作る実行物になります。

あと、地味によく当たるのが JSON です。  
`System.Text.Json` を普段のノリで reflection 寄りに使うより、source generation に寄せたほうが穏やかです。

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

Native AOT 対応というより、**実行時に型を探させない** 書き方へ寄せる、と覚えておくと外しにくいです。

## 7. どこから試すのがいいのか

最初の対象は、次のどれかが入りやすいです。

- 起動が大事な CLI
- worker
- 小さな Web API
- ネイティブ連携の中でも責務が狭い部品

このへんなら、動的な仕組みを減らしやすく、Native AOT のうれしさも見えやすいです。

逆に、WPF / WinForms の既存大規模アプリ本体、plugin 読み込みが主役の構成、COM 依存の強い構成は、最初の対象としてはあまり穏やかではありません。

## 8. まとめ

Native AOT は、.NET を publish 時にかなり静的に固める仕組みです。

- 起動には効きやすい
- 配布もしやすくなる
- その代わり、動的な仕組みには厳しくなる

この 3 つを最初に押さえておくと、見通しはかなり良くなります。

Native AOT は「全部の .NET アプリに付ける標準スイッチ」ではありません。  
でも、起動が大事、配布を軽くしたい、実行環境の前提を減らしたい、という場面ではかなり強い選択肢です。

逆に、Windows デスクトップや COM の濃い世界では、まだ普通の .NET のほうが筋が良いことも多いです。  
ここを見分けられると、Native AOT は「難しい新機能」ではなく、使いどころのはっきりした道具に見えてきます。

## 9. 参考資料

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
