---
title: "COMのSTA/MTAでハングを避けるための基礎知識"
date: 2026-01-31 10:00
tags: [COM, Windows開発, STA, MTA, スレッド]
author: Go Komura
---

# COMのSTA/MTAでハングを避けるための基礎知識

## 目次

1. [まず結論（ひとことで）](#1-まず結論ひとことで)
2. [Apartment Modelの呼び出しパターン（図）](#2-apartment-modelの呼び出しパターン図)
   - [2.1. パターン1: 同一STAスレッド内での呼び出し](#21-パターン1-同一staスレッド内での呼び出し)
   - [2.2. パターン2: 同一MTA内での呼び出し](#22-パターン2-同一mta内での呼び出し)
   - [2.3. パターン3: Apartmentを跨ぐ呼び出し](#23-パターン3-apartmentを跨ぐ呼び出し)
   - [2.4. マーシャリングのオーバーヘッド目安](#24-マーシャリングのオーバーヘッド目安)
3. [STA（Single-Threaded Apartment）](#3-stasingle-threaded-apartment)
   - [3.1. なぜUIスレッドでSTAが使われるのか](#31-なぜuiスレッドでstaが使われるのか)
4. [MTA（Multi-Threaded Apartment）](#4-mtamulti-threaded-apartment)
5. [STA/MTAはどこで決まるのか](#5-stamtaはどこで決まるのか)
   - [5.1. .NETでのSTA/MTA](#51-netでのstamta)
6. [STAを間違えると起きるハングの具体例](#6-staを間違えると起きるハングの具体例)
   - [6.1. よくある状況](#61-よくある状況)
   - [6.2. 何が起きるのか](#62-何が起きるのか)
   - [6.3. 擬似コード（典型的な失敗パターン）](#63-擬似コード典型的な失敗パターン)
   - [6.4. 回避の要点](#64-回避の要点)
   - [6.5.「メッセージループを回す」って結局なに？](#65メッセージループを回すって結局なに)
   - [6.6. 正しい方向の例（雑に書くとこう）](#66-正しい方向の例雑に書くとこう)
   - [6.7. もう一つのハング例: 同期呼び出し中のコールバック](#67-もう一つのハング例-同期呼び出し中のコールバック)
7. [ざっくり使い分け](#7-ざっくり使い分け)
8. [まとめ](#8-まとめ)
9. [参考資料](#9-参考資料)

---

COMを使うとき、**「どのスレッドで動くか」**は避けて通れません。  
その中心にあるのが **Apartment Model（STA/MTA）** です。

STA/MTAは**COMのためのスレッドモデル**です。  
Windowsの一般的なスレッド概念ではなく、COMオブジェクトの呼び出し規則を決めるための仕組みです。

この記事では、STAとMTAとCOMの関係を**図で整理**し、  
**「なぜハングすることがあるのか」**までつなげて説明します。

## 1. まず結論（ひとことで）

- **COMオブジェクトは「どのApartmentに所属するか」で呼び出し規則が決まる**
- STAは **1スレッドに1Apartment**、MTAは **複数スレッドで1Apartment** と考えると理解しやすい
- Apartmentを跨ぐ呼び出しは、**COMがProxy/Stub経由でマーシャリング**する

## 2. Apartment Modelの呼び出しパターン（図）

COMオブジェクトの呼び出しには、大きく3つのパターンがあります。

### 2.1. パターン1: 同一STAスレッド内での呼び出し

同じSTAスレッド内なら、**直接呼び出し**できます。オーバーヘッドなし。

<pre class="mermaid">
flowchart LR
    subgraph STA[STAスレッド]
        Caller[呼び出し元コード]
        Obj[COMオブジェクト]
        Caller -->|直接呼び出し| Obj
    end
</pre>

### 2.2. パターン2: 同一MTA内での呼び出し

MTA内の複数スレッドからは、**どのスレッドからでも直接呼び出し**できます。  
ただしオブジェクト側は**スレッドセーフ設計が必須**。

<pre class="mermaid">
flowchart LR
    subgraph MTA[MTA（1つのApartment）]
        Thread1[ワーカースレッド1]
        Thread2[ワーカースレッド2]
        Obj[COMオブジェクト]
        Thread1 -->|直接呼び出し| Obj
        Thread2 -->|直接呼び出し| Obj
    end
</pre>

### 2.3. パターン3: Apartmentを跨ぐ呼び出し

異なるApartment間では、**COMがProxy/Stubを使って**転送します。  
標準的なインターフェースならCOMランタイムが処理してくれます。

**注意:** Proxy/Stubは「何でも自動生成される」わけではありません。  
ただし、実務では多くの場合、明示的な生成は不要です。

| パターン | Proxy/Stubの準備 |
|---|---|
| `IDispatch` ベース（Automation） | 不要。`oleaut32.dll` が処理 |
| タイプライブラリ登録済み | 不要。タイプライブラリマーシャラーが処理 |
| .NET COM Interop | 通常は不要。タイプライブラリ経由で動く |
| `IUnknown` 直接派生のカスタムIF | MIDLでProxy/Stub生成・登録が必要 |

つまり、**MIDLでProxy/Stub生成が必要になるのは、`IDispatch` を使わず `IUnknown` 直接派生のインターフェースを作る場合**です。  
.NETやスクリプト言語から使う一般的なCOMコンポーネントでは、この作業が必要になることは少ないです。

<pre class="mermaid">
flowchart LR
    subgraph STA[STAスレッド]
        StaCaller[呼び出し元コード]
    end

    subgraph RT[COMランタイム（自動）]
        Proxy[Proxy]
        RPC[RPC/IPC]
        Stub[Stub]
        Proxy --> RPC --> Stub
    end

    subgraph MTA[MTAスレッド]
        MtaObj[COMオブジェクト]
    end

    StaCaller -->|呼び出し| Proxy
    Stub -->|転送| MtaObj
</pre>

**ポイント:**  
Apartmentを跨ぐと**マーシャリングのオーバーヘッド**が発生します。  
高頻度の呼び出しでは性能に影響するため、設計時に考慮が必要です。

### 2.4. マーシャリングのオーバーヘッド目安

以下は一般的な目安です（実測値ではなく、状況・パラメータの複雑さで大きく変わります）。

| 呼び出しパターン | 目安の時間 | 相対的な感覚 |
|---|---|---|
| 同一Apartment内（直接） | 10〜100ナノ秒 | 通常の関数呼び出しとほぼ同じ |
| 異なるApartment（同一プロセス） | 1〜10マイクロ秒 | 直接呼び出しの100〜1000倍 |
| 異なるプロセス（Out-of-proc） | 100〜1000マイクロ秒 | 直接呼び出しの1万〜10万倍 |

**相対的な比較:**
- 同一Apartment: 1回のメモリアクセス程度
- 異なるApartment: 1回のシステムコール程度
- 異なるプロセス: ローカルホストへのネットワーク通信程度

ループで1万回呼ぶような場面では、この差が顕著に効いてきます。

## 3. STA（Single-Threaded Apartment）

STAは**「1スレッド = 1Apartment」**というモデルです。

- そのApartment内のCOMオブジェクトは、**基本的にそのスレッドでのみ実行**
- 別スレッドから呼ぶと、**COMがメッセージキュー/RPC経由で呼び出しを転送**
- UIスレッド（WinForms/WPF）でよく使われる（UIも「1スレッド親和性＋メッセージループ」なので相性が良い）

### 3.1. なぜUIスレッドでSTAが使われるのか

UIスレッドとSTAは**設計が一致している**からです。

- **UIコントロールはスレッドセーフではない**  
  ボタンやテキストボックスなどは、生成したスレッドからしか安全に操作できない
- **STAも同じく「1スレッド親和性」**  
  COMオブジェクトは生成したスレッドでのみ直接実行される
- **UIスレッドは必ずメッセージループを回す**  
  ウィンドウイベントを処理するために必須。STAの前提（メッセージポンプ）と一致する

だからWinForms/WPFのUIスレッドは**デフォルトでSTA**になっています。

**ポイント:**  
STAはスレッド親和性が高い代わりに、**呼び出し元が多いと渋滞しやすい**。

## 4. MTA（Multi-Threaded Apartment）

MTAは**「複数スレッドで1Apartment」**というモデルです。

- COMオブジェクトは複数スレッドから同時に呼び出される
- オブジェクト側で**スレッドセーフ設計が必須**
- サーバーサイド処理やバックグラウンド処理向き

**ポイント:**  
MTAは並列性が高いが、**オブジェクト実装の責任が重い**。

## 5. STA/MTAはどこで決まるのか

COMのApartmentは、**スレッドごとに初期化する**ことで決まります。

- `CoInitialize` / `CoInitializeEx` を呼んだ瞬間に、そのスレッドのApartmentが決まる  
- STA: `COINIT_APARTMENTTHREADED`  
- MTA: `COINIT_MULTITHREADED`

### 5.1. .NETでのSTA/MTA

.NETにも `[STAThread]` / `[MTAThread]` 属性や `ApartmentState` がありますが、これらは**COMのApartment Modelを設定するためのラッパー**です。

- `[STAThread]` → **Mainメソッド（エントリポイント）に付ける**。COMを使う際にSTAとして初期化される
- `[MTAThread]` → 同様にMainメソッド用。MTAとして初期化される
- `Thread.SetApartmentState(ApartmentState.STA)` → **追加で作るスレッド用**。スレッド開始前に設定が必要

**注意点:**
- `[STAThread]` があっても、**実際にCOMを呼ぶまでは初期化されない**（COMを使わないなら効果なし）
- 追加スレッドには `[STAThread]` は効かない。`Thread.SetApartmentState` を使う

つまり、**.NETのSTA/MTAはCOMのSTA/MTAそのもの**です。  
.NET独自のスレッドモデルではなく、COM Interopのために用意された仕組みです。

**重要:**  
後からApartmentを変更することはできません。**最初の初期化が全て**です。

## 6. STAを間違えると起きるハングの具体例

次のような構成は、**実際にハングを引き起こしやすい**です。

### 6.1. よくある状況

- バックグラウンドでSTAスレッドを作成してCOMオブジェクトを生成  
- そのスレッドは**メッセージループを回していない**  
- 別スレッド（**STA/MTA問わず**）からそのCOMオブジェクトを呼び出す

### 6.2. 何が起きるのか

STAのCOMオブジェクトは、**呼び出しをそのSTAスレッドで処理する必要**があります。  
呼び出し元がSTAでもMTAでも、**別スレッドならCOMがメッセージ/RPCで転送**します。

ところがSTAスレッドが**メッセージを処理しない状態**だと、  
呼び出しはずっと待たされ、**結果としてハング**します。

### 6.3. 擬似コード（典型的な失敗パターン）

```csharp
var ready = new AutoResetEvent(false);
var done = new AutoResetEvent(false);

object comObj = null;
var staThread = new Thread(() =>
{
    // STAとして初期化
    CoInitializeEx(IntPtr.Zero, COINIT_APARTMENTTHREADED);

    comObj = new SomeStaComObject();
    ready.Set();

    // メッセージループがないまま待機 -> ここが致命傷
    done.WaitOne();
});

staThread.SetApartmentState(ApartmentState.STA);
staThread.Start();

ready.WaitOne();

// 別スレッド（STA/MTA問わず）から呼ぶと、呼び出しがSTAに転送される
// しかしSTA側はメッセージを処理しないため、ここでハングしやすい
CallComObject(comObj);
```

<pre class="mermaid">
sequenceDiagram
    participant Main as メインスレッド
    participant STA as STAスレッド
    participant COM as COMランタイム

    Main->>STA: スレッド開始
    STA->>STA: CoInitializeEx（STA）
    STA->>STA: COMオブジェクト生成
    STA->>Main: ready.Set()
    STA->>STA: done.WaitOne()で待機
    Note over STA: メッセージループなし<br/>ここで詰まっている

    Main->>COM: CallComObject()
    COM->>STA: 呼び出しを転送しようとする
    Note over COM: メッセージで転送するが...
    Note over STA: WaitOne中なので<br/>メッセージを処理できない
    Note over Main: 呼び出し元も待ち続ける
    Note over Main,STA: 両方が待ち状態 → ハング
</pre>

**要するに:**  
ここで言う「前提」は、**「STAで別スレッド呼び出しがハングする理由」**を説明するための前提です。  
STAの前提は**次の2つ**です。

- **COMオブジェクトは生成したSTAスレッドで処理される**  
  別スレッドからの呼び出しは、必ずそのSTAスレッドに転送される
- **その転送を受け取るために、STAスレッドはメッセージポンプを回す**  
  回していないと呼び出しを受け取れない

だから、

- **メッセージを回していないSTAスレッド**は呼び出しを受け取れない  
- 受け取れないので呼び出し元が待ち続け、結果として**ハング**する  

一方、UIスレッドは**ウィンドウイベントを処理するために最初からメッセージループを回している**ので、STAの要件を追加実装なしで満たしています。  
だからUIスレッドはSTAのCOMオブジェクトを動かす場所として自然な選択肢になります。

### 6.4. 回避の要点

- **別スレッドからの呼び出しを受ける場合**、STAスレッドはメッセージループを回す必要がある
- 可能なら**UIスレッド上で生成・利用する**（UIスレッドは最初からメッセージループがある）
- STAが不要なら**最初からMTAにする**

**補足:** 同一スレッド内だけで完結するなら、常に `Application.Run()` が必要とは限りません。  
ただし、UI系・COM系は別スレッドからの呼び出しが絡むことが多いため、実務上はほぼ必須です。

### 6.5.「メッセージループを回す」って結局なに？

Win32のUIスレッドがやっている、例のこれです。

```csharp
while (GetMessage(out var msg, IntPtr.Zero, 0, 0))
{
    TranslateMessage(ref msg);
    DispatchMessage(ref msg);
}
```

STAでは、別スレッドからの呼び出しが「転送」されてきます。  
その転送を**受け取って実行に回す**のが、このループ（メッセージポンプ）だ、という話です。

### 6.6. 正しい方向の例（雑に書くとこう）

「バックグラウンドSTAでCOMを使いたい」なら、こういう形になります。

```csharp
var ready = new AutoResetEvent(false);
object comObj = null;

var staThread = new Thread(() =>
{
    CoInitializeEx(IntPtr.Zero, COINIT_APARTMENTTHREADED);

    comObj = new SomeStaComObject();
    ready.Set();

    // STAスレッドが生きている間はメッセージを回す
    Application.Run();

    CoUninitialize();
});

staThread.SetApartmentState(ApartmentState.STA);
staThread.Start();

ready.WaitOne();
CallComObject(comObj);
```

（※ `CoInitializeEx` / `CoUninitialize` の呼び忘れは普通に事故ります）

### 6.7. もう一つのハング例: 同期呼び出し中のコールバック

STAは「呼び出しが転送される」だけでなく、状況によっては**逆方向（サーバー→クライアント）にコールバック**が来ます。  
**同期呼び出し中にコールバックが発生するパターン**は、デッドロックの原因になりやすいです。

<pre class="mermaid">
sequenceDiagram
    participant UI as UIスレッド（STA）
    participant Server as COMサーバー

    UI->>Server: DoWork()（同期呼び出し）
    Note over UI: DoWorkの戻りを待っている<br/>（メッセージを処理していない）
    Server->>UI: ProgressCallback()（コールバック）
    Note over UI: 待機中なので<br/>コールバックを受け取れない
    Note over Server: コールバックの完了を待っている
    Note over UI,Server: お互いが相手を待っている → デッドロック
</pre>

**なぜデッドロックになりやすいのか:**

1. UIスレッドが `DoWork()` を**同期呼び出し**（ブロッキング）
2. UIスレッドは戻りを待っている（メッセージを処理していない）
3. サーバーが `ProgressCallback()` をUIスレッドに送る
4. UIスレッドは待機中なので**コールバックを受け取れない**
5. サーバーはコールバックの完了を待っている
6. **お互いが相手を待っている → 永遠に進まない**

処理時間の長さは関係ありません。**同期呼び出し中にコールバックが来る**というパターン自体が問題になりやすいです。

**補足:** COMには状況によってメッセージを回す・再入する仕組みもあり、コンポーネントや呼び出し形態で挙動が変わります。  
必ずデッドロックになるわけではありませんが、このパターンは避けるのが無難です。

## 7. ざっくり使い分け

- **UIが絡む → STA**
- **大量並列処理 → MTA**
- **どちらでもない → 既存ライブラリやCOMサーバーの要求に合わせる**

## 8. まとめ

**STA/MTAとは:**
- STA/MTAは**COMのためのスレッドモデル**（Windowsの一般的なスレッド概念ではない）
- STAは**1スレッド = 1Apartment**、MTAは**複数スレッドで1Apartment**
- Apartmentを跨ぐと**COMがProxy/Stub経由で転送**する（標準IF以外はMIDL等での生成・登録が必要）

**STAの前提と落とし穴:**
- **別スレッドからの呼び出しを受ける場合**、STAはメッセージポンプを回すことが前提
- メッセージを回していないSTAスレッドに呼び出すと**ハングしやすい**
- **同期呼び出し中にコールバックが来る**パターンは**デッドロックになりやすい**

**UIスレッドとSTAの関係:**
- UIスレッドは「1スレッド親和性」と「メッセージループ」を最初から持っている
- だからSTAの要件を追加実装なしで満たしており、**STAのCOMと相性が良い**

**設計時の注意:**
- Apartmentを跨ぐ呼び出しには**マーシャリングのオーバーヘッド**がある
- 高頻度の呼び出しでは性能に影響するため、Apartment設計は慎重に

## 9. 参考資料

- Apartment Model  
  https://learn.microsoft.com/en-us/windows/win32/com/com-apartments
- CoInitializeEx  
  https://learn.microsoft.com/en-us/windows/win32/api/objbase/nf-objbase-coinitializeex
