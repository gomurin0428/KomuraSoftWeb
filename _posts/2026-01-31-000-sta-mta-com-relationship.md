---
title: "STAとMTAとCOMの関係を図で理解する"
date: 2026-01-31 10:00
tags: [COM, Windows開発, STA, MTA, スレッド]
author: Go Komura
---

# STAとMTAとCOMの関係を図で理解する

COMを使うとき、**「どのスレッドで動くか」**は避けて通れません。  
その中心にあるのが **Apartment Model（STA/MTA）** です。

STA/MTAは**COMのためのスレッドモデル**です。  
Windowsの一般的なスレッド概念ではなく、COMオブジェクトの呼び出し規則を決めるための仕組みです。

この記事では、STAとMTAとCOMの関係を**図で整理**し、  
**「なぜハングすることがあるのか」**までつなげて説明します。

## まず結論（ひとことで）

- **COMオブジェクトは「どのApartmentに所属するか」で呼び出し規則が決まる**
- STAは **1スレッドに1Apartment**、MTAは **複数スレッドで1Apartment** と考えると理解しやすい
- Apartmentを跨ぐ呼び出しは、**COMがProxy/Stubで自動的にマーシャリング**する

## Apartment Modelの全体像（図）

<pre class="mermaid">
flowchart LR
    subgraph STA[STAスレッド（例: UI）]
        direction TB
        StaCaller[呼び出し元コード]
        StaObj[STAのCOMオブジェクト]
        StaCaller -->|同一スレッドなら直接| StaObj
    end

    subgraph MTA[MTA（ワーカースレッド群）]
        direction TB
        MtaCaller[呼び出し元コード]
        MtaObj[MTAのCOMオブジェクト]
        MtaCaller -->|同一Apartmentなら直接| MtaObj
    end

    subgraph RT[COMランタイム（自動）]
        direction TB
        Proxy[Proxy]
        RPC[RPC/IPC]
        Stub[Stub]
        Proxy --> RPC --> Stub
    end

    StaCaller -->|Apartmentを跨ぐ| Proxy
    MtaCaller -->|Apartmentを跨ぐ| Proxy
    Stub -->|本来の所属スレッドへ転送| StaObj
    Stub -->|本来の所属スレッドへ転送| MtaObj
</pre>

## STA（Single-Threaded Apartment）

STAは**「1スレッド = 1Apartment」**というモデルです。

- そのApartment内のCOMオブジェクトは、**基本的にそのスレッドでのみ実行**
- 別スレッドから呼ぶと、**COMがメッセージキュー/RPC経由で呼び出しを転送**
- UIスレッド（WinForms/WPF）でよく使われる（UIも「1スレッド親和性＋メッセージループ」なので相性が良い）

### なぜUIスレッドでSTAが使われるのか

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

## MTA（Multi-Threaded Apartment）

MTAは**「複数スレッドで1Apartment」**というモデルです。

- COMオブジェクトは複数スレッドから同時に呼び出される
- オブジェクト側で**スレッドセーフ設計が必須**
- サーバーサイド処理やバックグラウンド処理向き

**ポイント:**  
MTAは並列性が高いが、**オブジェクト実装の責任が重い**。

## STA/MTAはどこで決まるのか

COMのApartmentは、**スレッドごとに初期化する**ことで決まります。

- `CoInitialize` / `CoInitializeEx` を呼んだ瞬間に、そのスレッドのApartmentが決まる  
- STA: `COINIT_APARTMENTTHREADED`  
- MTA: `COINIT_MULTITHREADED`

### .NETでのSTA/MTA

.NETにも `[STAThread]` / `[MTAThread]` 属性や `ApartmentState` がありますが、これらは**COMのApartment Modelを設定するためのラッパー**です。

- `[STAThread]` → 内部で `CoInitializeEx(COINIT_APARTMENTTHREADED)` を呼ぶ
- `[MTAThread]` → 内部で `CoInitializeEx(COINIT_MULTITHREADED)` を呼ぶ
- `Thread.SetApartmentState(ApartmentState.STA)` → 同様

つまり、**.NETのSTA/MTAはCOMのSTA/MTAそのもの**です。  
.NET独自のスレッドモデルではなく、COM Interopのために用意された仕組みです。

**重要:**  
後からApartmentを変更することはできません。**最初の初期化が全て**です。

## STAを間違えると起きるハングの具体例

次のような構成は、**実際にハングを引き起こしやすい**です。

### よくある状況

- バックグラウンドでSTAスレッドを作成してCOMオブジェクトを生成  
- そのスレッドは**メッセージループを回していない**  
- 別スレッド（**STA/MTA問わず**）からそのCOMオブジェクトを呼び出す

### 何が起きるのか

STAのCOMオブジェクトは、**呼び出しをそのSTAスレッドで処理する必要**があります。  
呼び出し元がSTAでもMTAでも、**別スレッドならCOMがメッセージ/RPCで転送**します。

ところがSTAスレッドが**メッセージを処理しない状態**だと、  
呼び出しはずっと待たされ、**結果としてハング**します。

### 擬似コード（典型的な失敗パターン）

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

### 回避の要点

- STAスレッドでは**必ずメッセージループを回す**（`Application.Run` など）
- 可能なら**UIスレッド上で生成・利用する**
- STAが不要なら**最初からMTAにする**

### 「メッセージループを回す」って結局なに？

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

### 正しい方向の例（雑に書くとこう）

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

### もう一つのハング例: 同期呼び出し中のコールバック

STAは「呼び出しが転送される」だけでなく、状況によっては**逆方向（サーバー→クライアント）にコールバック**が来ます。  
**同期呼び出し中にコールバックが発生するパターン**は、デッドロックの原因になります。

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

**なぜデッドロックになるのか:**

1. UIスレッドが `DoWork()` を**同期呼び出し**（ブロッキング）
2. UIスレッドは戻りを待っている（メッセージを処理していない）
3. サーバーが `ProgressCallback()` をUIスレッドに送る
4. UIスレッドは待機中なので**コールバックを受け取れない**
5. サーバーはコールバックの完了を待っている
6. **お互いが相手を待っている → 永遠に進まない**

処理時間の長さは関係ありません。**同期呼び出し中にコールバックが来る**というパターン自体が問題です。

## ざっくり使い分け

- **UIが絡む → STA**
- **大量並列処理 → MTA**
- **どちらでもない → 既存ライブラリやCOMサーバーの要求に合わせる**

## まとめ

- COMのApartmentは**「COMオブジェクトの動作スレッドを決める仕組み」**
- STAは**スレッド親和性重視**、MTAは**並列性重視**
- Apartmentを跨ぐと**COMが自動でProxy/Stubを挟む**

この理解があると、**「なぜUIスレッドで呼ぶ必要があるのか」**が腹落ちします。

## 参考資料

- Apartment Model  
  https://learn.microsoft.com/en-us/windows/win32/com/com-apartments
- CoInitializeEx  
  https://learn.microsoft.com/en-us/windows/win32/api/objbase/nf-objbase-coinitializeex
