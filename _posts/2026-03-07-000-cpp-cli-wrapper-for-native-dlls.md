---
title: "C# からネイティブ DLL を使うなら C++/CLI ラッパーが有力な理由 - P/Invoke と比較して整理"
date: 2026-03-07 10:00
tags: [C++/CLI, C#, Windows開発, ネイティブ連携]
author: Go Komura
description: "C# からネイティブ DLL を呼び出すときに、P/Invoke で十分なケースと C++/CLI ラッパーが有力になるケースを、所有権や例外、C++ 型の扱いまで含めて整理します。"
---

Windows の既存資産や既存 DLL を C# から使いたい、という要件はかなりよくあります。
相手が Win32 API のような素直な C インターフェースなら、P/Invoke で十分です。

ただ、実務で出てくるのはもっと癖のある DLL です。
C++ のクラスがあり、所有権の流儀があり、例外も飛び、`std::wstring` や `std::vector` も普通に出てきます。
ここで P/Invoke だけで押し切ると、たいてい境界面がだんだん苦しくなります。

この記事では、そういうときに **C++/CLI で薄いラッパーを 1 枚挟む** と何が楽になるのかを整理します。
P/Invoke が悪い、という話ではありません。
**P/Invoke で十分な場面と、C++/CLI が効く場面は違う** という話です。

## 目次

1. まず結論（ひとことで）
2. P/Invoke で十分なケース
3. P/Invoke が急にしんどくなる境界
4. C++/CLI ラッパーを挟む構成
5. C++/CLI で何が楽になるのか
6. コード抜粋
7. それでも C++/CLI を選ばないほうがよいケース
8. まとめ
9. 参考資料

* * *

## 1. まず結論（ひとことで）

- **相手が C の関数群なら、P/Invoke が素直**
- **相手が C++ のライブラリなら、C++/CLI ラッパーを 1 枚挟むと保守しやすい**
- 特に **クラス・所有権・文字列・配列・例外・コールバック** が絡むなら、C# 側に無理をさせないほうがよい

要するに、**C# にネイティブ DLL の都合を直接持ち込まない** ということです。
ネイティブの都合は C++ 側で受けて、.NET に見せる面だけを整える。
この分業がうまくいくと、コードもデバッグもかなり穏やかになります。

## 2. P/Invoke で十分なケース

最初に大事なことを言うと、P/Invoke で片付くなら、それがいちばん簡単です。
無理に C++/CLI を持ち込む必要はありません。

P/Invoke が向いているのは、たとえば次のようなケースです。

- `extern "C"` で公開されたフラットな関数 API になっている
- 引数や戻り値が、整数・ポインタ・単純な構造体などで済む
- 文字列の規約が明確で、バッファの責務も単純
- リソース管理が `Create` / `Destroy` のように分かりやすい
- C# 側で `SafeHandle` や `StructLayout` を素直に書ける

このくらい整っているなら、C# 側で宣言して使うだけです。
Windows API を呼ぶ感覚に近いので、実装も読みやすいです。

## 3. P/Invoke が急にしんどくなる境界

問題は、相手が「ただの C API」ではないときです。
ここから急に空気が変わります。

### 3.1. C++ のクラスを相手にし始めたとき

ネイティブ DLL が C++ のクラス中心で設計されている場合、C# から直接見たいのは本当はメソッドですが、P/Invoke で直接相手にできるのは **DLL のエクスポート関数** です。
つまり、結局どこかで **C 形式の関数に落とす層** が必要になります。

この時点で、やっていることはほぼ「ラッパーを書く」です。
だったら、C# 側に `IntPtr` と解放関数を大量に生やすより、**C++ 側にラッパーを寄せたほうが自然** です。

### 3.2. 所有権と寿命管理が見えにくいとき

C++ では、

- 呼び出し側が解放するのか
- 返されたポインタは借り物なのか
- `const&` なのか所有権移動なのか
- 内部でキャッシュしていて寿命に前提があるのか

といった話が普通にあります。

これを C# の `IntPtr` ベースで表現すると、最初は動いても、後で読み返したときにかなりつらいです。
「このポインタ、誰がいつ消すんだっけ問題」が始まると、境界面はすぐ濁ります。

### 3.3. `std::wstring`、`std::vector`、コールバック、例外が出てきたとき

この辺から、P/Invoke は「書けなくはないが、気持ちよくはない」領域に入ります。

- `std::wstring` をそのまま C# から表したい
- `std::vector<T>` を返したい
- ネイティブ処理の進捗をコールバックで受けたい
- 失敗時に C++ 例外が飛ぶ

こういう要素が増えると、C# 側に `MarshalAs`、手動バッファ、固定長配列、デリゲート寿命管理、エラーコード解釈などが増えてきます。

もちろん頑張れば書けます。
ただ、**がんばりどころが本質ではない** のがつらいところです。
本来やりたいのは業務ロジックや UI であって、境界面の格闘技ではありません。

### 3.4. C++ の都合を C# に漏らしたくないとき

ネイティブ DLL 側の API がそのまま C# に向いているとは限りません。

たとえばネイティブ側では、

- 複数のメソッド呼び出しを組み合わせて 1 回の処理にする
- エラーは戻り値と out 引数で返す
- 初期化順序に前提がある
- スレッドセーフ性に制約がある

という設計でも、C# 側にはもっと素直な API を見せたいことが多いです。
ここを変換する層として、C++/CLI はかなり都合がよいです。

## 4. C++/CLI ラッパーを挟む構成

構成としてはシンプルです。

```mermaid
flowchart LR
    Cs[C# アプリ] -->|.NET 向けの API| Wrapper[C++/CLI ラッパー DLL]
    Wrapper -->|ネイティブのヘッダーや型を直接扱う| Native[ネイティブ C++ DLL]
```

C# から見えるのは **.NET らしい API** だけにして、

- 文字列変換
- 配列やベクターの変換
- 例外の変換
- 所有権の整理
- エラーコードの解釈
- 必要ならスレッド境界やコールバックの吸収

を C++/CLI 側に閉じ込めます。

大事なのは、**C++/CLI プロジェクト自体を大きくしすぎない** ことです。
役割はあくまで「翻訳」と「整形」です。
業務ロジックまで入れ始めると、今度はその層が主役になってしまいます。

## 5. C++/CLI で何が楽になるのか

### 5.1. C++ の型を C++ のまま扱える

これはかなり大きいです。
C++/CLI 側ではネイティブのヘッダーをインクルードして、そのまま C++ の型を使えます。

つまり、C# 側で無理に「C++ の世界を再現」しなくて済みます。
`std::wstring` も `std::vector` も、まずは C++ の型として受け止めてから、必要な形で .NET 側に渡せばよいです。

### 5.2. API を .NET 向けに整形できる

C# 側には、

- `string`
- `byte[]`
- `List<T>`
- `IDisposable`
- 例外

といった、見慣れた形で API を出せます。

この差は地味に見えて、使う側の負担を大きく変えます。
特にチーム開発だと、ネイティブ事情を知らないメンバーでも触りやすくなるのが効きます。

### 5.3. 例外とエラーの責務を整理しやすい

ネイティブ側で例外やエラーコードが混在していると、C# 側でそのまま受けるのは扱いづらいです。
C++/CLI 側で一度まとめて、

- 例外は .NET の例外へ変換する
- エラーコードは意味のある例外や結果型に変換する
- ログに必要な文脈を補う

といったことができます。

境界で一度「意味のある失敗」に翻訳しておくと、呼び出し側はかなりすっきりします。

### 5.4. ABI の揺れを C# 側から隠せる

C++ のクラスやメソッドは、C の関数のように単純な ABI ではありません。
C# が直接その事情を知り始めると、エクスポート関数やマーシャリングの都合が表に出てきます。

C++/CLI ラッパーを挟めば、**C++ の都合は C++ 側に閉じ込めて、C# には安定した面だけを見せる** ことができます。
この分離は、ライブラリ更新時にも効きます。

### 5.5. 段階的移行がしやすい

既存のネイティブ DLL をいきなり全部作り直すのは重いです。
C++/CLI ラッパーなら、まずは必要な API だけ薄く包み、C# 側の新しい画面やワークフローから使い始める、という段階的な移行がしやすいです。

Windows の既存資産を活かしながら周辺を .NET に寄せる、という場面ではかなり相性がよいです。

## 6. コード抜粋

ここでは「そのまま動く完全なサンプル」ではなく、境界面のイメージが分かる程度の抜粋だけ載せます。

### 6.1. ネイティブ DLL 側の API イメージ

```cpp
// NativeLib.hpp
#pragma once
#include <string>
#include <vector>

namespace NativeLib
{
    struct AnalyzeOptions
    {
        int threshold;
        std::wstring modelPath;
    };

    struct AnalyzeResult
    {
        bool ok;
        std::wstring message;
        std::vector<int> scores;
    };

    class Analyzer
    {
    public:
        explicit Analyzer(const std::wstring& licensePath);
        AnalyzeResult Analyze(const std::wstring& imagePath, const AnalyzeOptions& options);
    };
}
```

この API は、ネイティブ C++ としては普通です。
でも C# からそのまま触るには、なかなか骨があります。

### 6.2. P/Invoke でやろうとするとこうなる

まず、C# から直接呼ぶためには、どこかで **C 形式の関数** に落とす必要があります。
たとえばこんなブリッジ関数を別途用意することになります。

```cpp
// C API に落としたブリッジのイメージ
extern "C"
{
    __declspec(dllexport) void* Analyzer_Create(const wchar_t* licensePath);
    __declspec(dllexport) void  Analyzer_Destroy(void* handle);

    __declspec(dllexport) int Analyzer_Analyze(
        void* handle,
        const wchar_t* imagePath,
        const AnalyzeOptionsNative* options,
        AnalyzeResultNative* result);
}
```

C# 側も、こんな雰囲気になります。

```csharp
internal sealed class SafeAnalyzerHandle : SafeHandle
{
    private SafeAnalyzerHandle() : base(IntPtr.Zero, ownsHandle: true) { }

    public override bool IsInvalid => handle == IntPtr.Zero;

    protected override bool ReleaseHandle()
    {
        NativeMethods.Analyzer_Destroy(handle);
        return true;
    }
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
internal struct AnalyzeOptionsNative
{
    public int Threshold;
    public IntPtr ModelPath;
}

internal static class NativeMethods
{
    [DllImport("NativeBridge.dll", CharSet = CharSet.Unicode)]
    internal static extern SafeAnalyzerHandle Analyzer_Create(string licensePath);

    [DllImport("NativeBridge.dll", CharSet = CharSet.Unicode)]
    internal static extern void Analyzer_Destroy(IntPtr handle);

    [DllImport("NativeBridge.dll", CharSet = CharSet.Unicode)]
    internal static extern int Analyzer_Analyze(
        SafeAnalyzerHandle handle,
        string imagePath,
        ref AnalyzeOptionsNative options,
        out AnalyzeResultNative result);
}
```

これで済むならよいのですが、実際にはさらに

- 可変長データをどう返すか
- 文字列バッファを誰が解放するか
- エラー詳細をどこに置くか
- コールバック寿命をどう守るか

といった論点が増えてきます。

つまり、**P/Invoke を選んだつもりが、実質的には C 互換 API の設計を始めている** ことが多いです。

### 6.3. C++/CLI ラッパーだとこう書ける

C++/CLI 側で、ネイティブの都合を受け止めて、C# に見せる API を整えます。

```cpp
// AnalyzerWrapper.h
#pragma once
#include "NativeLib.hpp"

using namespace System;
using namespace System::Collections::Generic;

public ref class AnalysisOptions
{
public:
    property int Threshold;
    property String^ ModelPath;
};

public ref class AnalysisResult
{
public:
    property bool Ok;
    property String^ Message;
    property List<int>^ Scores;
};

public ref class AnalyzerWrapper : IDisposable
{
public:
    AnalyzerWrapper(String^ licensePath);
    ~AnalyzerWrapper();
    !AnalyzerWrapper();

    AnalysisResult^ Analyze(String^ imagePath, AnalysisOptions^ options);

private:
    NativeLib::Analyzer* _native;
};
```

```cpp
// AnalyzerWrapper.cpp
#include "AnalyzerWrapper.h"
#include <msclr/marshal_cppstd.h>

using msclr::interop::marshal_as;

AnalyzerWrapper::AnalyzerWrapper(String^ licensePath)
{
    _native = new NativeLib::Analyzer(marshal_as<std::wstring>(licensePath));
}

AnalyzerWrapper::~AnalyzerWrapper()
{
    this->!AnalyzerWrapper();
}

AnalyzerWrapper::!AnalyzerWrapper()
{
    delete _native;
    _native = nullptr;
}

AnalysisResult^ AnalyzerWrapper::Analyze(String^ imagePath, AnalysisOptions^ options)
{
    NativeLib::AnalyzeOptions nativeOptions{};
    nativeOptions.threshold = options->Threshold;
    nativeOptions.modelPath = marshal_as<std::wstring>(options->ModelPath);

    try
    {
        auto nativeResult = _native->Analyze(
            marshal_as<std::wstring>(imagePath),
            nativeOptions);

        auto managed = gcnew AnalysisResult();
        managed->Ok = nativeResult.ok;
        managed->Message = gcnew String(nativeResult.message.c_str());
        managed->Scores = gcnew List<int>();

        for (int score : nativeResult.scores)
        {
            managed->Scores->Add(score);
        }

        return managed;
    }
    catch (const std::exception& ex)
    {
        throw gcnew InvalidOperationException(gcnew String(ex.what()));
    }
}
```

C# 側はかなり素直になります。

```csharp
using var analyzer = new AnalyzerWrapper(@"C:\license.dat");

var result = analyzer.Analyze(
    @"C:\input.png",
    new AnalysisOptions
    {
        Threshold = 80,
        ModelPath = @"C:\model.bin"
    });

if (!result.Ok)
{
    Console.WriteLine(result.Message);
}
```

C# から見えるのは、`string` と `List<int>` と `IDisposable` です。
`IntPtr` や解放関数やネイティブ文字列バッファの都合は見えません。
ここが大きいです。

## 7. それでも C++/CLI を選ばないほうがよいケース

もちろん、C++/CLI は万能ではありません。
選ばないほうがよい場面もあります。

- **相手が最初からきれいな C API を公開している**
  - この場合は P/Invoke のほうが素直です。
- **クロスプラットフォームが必要**
  - C++/CLI は Windows 前提です。
- **境界面が小さく、型も単純**
  - ラッパー DLL を増やすコストのほうが大きいことがあります。
- **AOT や配布制約をかなり厳密に見ている**
  - 構成全体の要件を先に見たほうがよいです。

つまり、判断基準は「ネイティブ DLL の複雑さに対して、どこで翻訳するのがいちばん自然か」です。
単純なら P/Invoke、複雑なら C++/CLI。
この切り分けでだいたいうまくいきます。

## 8. まとめ

C# からネイティブ DLL を使う方法として、P/Invoke は今でも王道です。
ただし、それは **相手が C API として素直なとき** の話です。

ネイティブ側が C++ ライブラリとして設計されているなら、
C# 側に `IntPtr` とマーシャリング属性を並べて頑張るより、**C++/CLI で薄いラッパーを作ったほうが境界面がきれいに保てる** ことが多いです。

特に、

- クラスベースの API
- 所有権の前提
- `std::wstring` や `std::vector`
- 例外変換
- コールバック
- 段階的な移行

が絡むなら、C++/CLI はかなり現実的な選択肢です。

やることは派手ではありません。
でも、こういう「境界をどこで整えるか」は、後の保守性にきっちり効いてきます。
Windows の既存資産と .NET を一緒に生かしたいとき、C++/CLI はまだまだ便利です。

## 9. 参考資料

- [Mixed (Native and Managed) Assemblies - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/mixed-native-and-managed-assemblies?view=msvc-170)
- [.NET programming with C++/CLI - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/dotnet-programming-with-cpp-cli-visual-cpp?view=msvc-170)
- [Migrate C++/CLI projects to .NET - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/core/porting/cpp-cli)
- [Using C++ Interop (Implicit PInvoke) - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/using-cpp-interop-implicit-pinvoke?view=msvc-170)
- [Platform Invoke (P/Invoke) - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke)
- [Overview of Marshaling in C++/CLI - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/overview-of-marshaling-in-cpp?view=msvc-170)
- [marshal_as - Microsoft Learn](https://learn.microsoft.com/ja-jp/cpp/dotnet/marshal-as?view=msvc-170)
- [Interop (C++) のパフォーマンスに関する考慮事項 - Microsoft Learn](https://learn.microsoft.com/ja-jp/cpp/dotnet/performance-considerations-for-interop-cpp?view=msvc-170)
