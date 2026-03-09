---
title: "Windowsでソフトリアルタイムをできるだけ実現するための実践ガイド - 設計、実装、電源設定、計測"
date: 2026-03-09 10:00
tags: [Windows開発, ソフトリアルタイム, 設計, 計測]
author: Go Komura
---

Windows で周期処理、音声処理、映像処理、計測、装置制御のような「遅れると困る」処理を作ると、「Windows では厳しいのでは」という印象を持たれがちです。  
これは半分正しく、半分は違います。 Windows は hard real-time OS ではありませんが、設計、実装、計測、運用をきちんと詰めると、soft real-time としてかなり実用的な状態まで持っていけます。

この記事では、Windows で **ソフトリアルタイムをできるだけ安定して実現する** ために、設計、実装、スレッド、タイマ、メモリ、電源設定、計測までを実務寄りに整理します。  
音声、映像、周期制御、データ取得では細部は違いますが、問題になりやすい点はかなり共通しています。 その共通部分を順番に見ていきます。

## 目次

1. まず結論（ひとことで）
2. Windows で「ソフトリアルタイム」とは何か
   - 2.1. 何ができるか
   - 2.2. どこから難しくなるか
3. 遅延とジッタの主な原因
   - 3.1. スケジューラと優先度
   - 3.2. DPC/ISR とドライバ
   - 3.3. ページフォルトとメモリ
   - 3.4. タイマ分解能と電源管理
   - 3.5. コア移動と熱
4. アンチパターン
   - 4.1. `Sleep` 任せの周期ループ
   - 4.2. ホットパスでブロッキング I/O
   - 4.3. ホットパスで確保・解放・GC
   - 4.4. 無制限キュー
   - 4.5. いきなり `REALTIME_PRIORITY_CLASS`
5. 設計の基本方針
   - 5.1. fast path / slow path を分ける
   - 5.2. 固定長キューとドロップ方針を先に決める
   - 5.3. マルチレート設計にする
   - 5.4. deadline miss を観測可能にする
6. 実装の基本方針
   - 6.1. 優先度の基本方針
   - 6.2. MMCSS を使う場面
   - 6.3. タイマと時計の選び方
   - 6.4. メモリの扱い
   - 6.5. CPU の置き方
   - 6.6. 周期ループの擬似コード
   - 6.7. .NET 側の注意
7. 電源設定・OS設定の考え方
   - 7.1. まず触る設定
   - 7.2. 電源プランの考え方
   - 7.3. Process Power Throttling / EcoQoS
   - 7.4. バックグラウンド負荷と運用
   - 7.5. BIOS / UEFI は最後に
8. 計測と評価
   - 8.1. 何を記録するか
   - 8.2. 何で見るか
   - 8.3. テストの作法
9. ざっくり使い分け
10. まとめ
11. 参考資料

* * *

## 1. まず結論（ひとことで）

- Windows で目指すのは hard real-time の保証ではなく、**遅延とジッタを抑え、deadline miss を少なくすること**
- 一番効果が大きいのは、**ホットパスを短く・固定長に・非ブロッキングにする設計**
- fast path（取得 / 制御）と slow path（保存 / 通信 / UI）を分け、間は **固定長キュー** でつなぐ
- 音声や映像のような連続ストリームでは、まず **MMCSS** を検討する
- 時間計測は **QueryPerformanceCounter / Stopwatch**、待機は **デバイスイベント** か **高精度 waitable timer** を優先する
- `timeBeginPeriod` は必要な間だけ使う。 常時有効にする前提で設計しない
- 実運用では **AC 給電 / 本番向けの電源設定 / HighQoS / バックグラウンド負荷の整理** が効く
- 評価は平均値ではなく、**p99 / p99.9 / max / miss 回数 / DPC/ISR / page fault / queue 深さ** で見る

要するに、Windows では **優先度を上げることより、遅れる理由を設計で減らすこと** のほうが効果的です。  
優先度や電源設定は重要ですが、それだけで安定性は作れません。

## 2. Windows で「ソフトリアルタイム」とは何か

### 2.1. 何ができるか

Windows では、たとえば次のような処理なら、かなり現実的に「遅れにくい」状態を作れます。

- 数ミリ秒〜数十ミリ秒の周期処理
- 音声 / 映像のバッファ駆動
- センサー取得と制御のループ
- 一定周期のソフト PLC 風処理
- UI とは別スレッドで動く低遅延パイプライン

ただし、ここでいう「できる」は、**たまの遅延スパイクを完全にゼロにできる** という意味ではありません。  
狙うのは、

- 通常時の遅延を低くする
- ジッタを小さくする
- たまに期限を外しても壊れない
- 外した事実を観測できる

という状態です。

### 2.2. どこから難しくなるか

難しくなるのは、たとえば次のような要求です。

- 期限違反ゼロを保証したい
- 数百マイクロ秒以下を長時間安定して守りたい
- 重い GUI やネットワークやストレージと同居したい
- ノート PC のバッテリー駆動や省電力優先のままやりたい
- ドライバやデバイス由来のスパイクも許されない

このあたりになると、user-mode の Windows だけで満たすのはかなり難しくなります。  
その場合は、**本当に時間に厳しい部分だけを、デバイス側のファームウェア、専用コントローラ、FPGA、別の RTOS、あるいは少なくとも Windows の外側に寄せる** ことも考えたほうがよいです。

大事なのは、**周期を守ること** と **周期が破れたときに壊れないこと** を分けて考えることです。  
前者はチューニングの話で、後者は設計の話です。

## 3. 遅延とジッタの主な原因

### 3.1. スケジューラと優先度

Windows のスレッドは優先度で実行順が決まります。  
同じ優先度ならラウンドロビンで回り、より高い優先度のスレッドが実行可能になると、低い優先度のスレッドはその場で押しのけられます。

つまり、周期スレッドを真面目に書いても、

- 別スレッド
- 別プロセス
- OS の内部処理
- セキュリティ製品
- デバイスまわりの補助処理

が先に走ることは普通にあります。

### 3.2. DPC/ISR とドライバ

ここはかなり重要です。  
アプリ側のスレッド優先度を整えても、**DPC（Deferred Procedure Call）や ISR（Interrupt Service Routine）** が長いと、その間は user-mode のスレッドは実行できません。

原因になりやすいのは、たとえば次です。

- USB
- Wi-Fi / Bluetooth
- ストレージ
- オーディオ
- GPU
- ACPI / 電源まわり

アプリのコードが悪くなくても、ドライバやハードウェアの都合で止められることがあります。  
ここはアプリ側だけでは完全に制御できません。

### 3.3. ページフォルトとメモリ

ホットパスでページフォルトが起きると、遅延が一気に大きくなります。  
特に避けたいのは、次のようなものです。

- 初回アクセスでのページコミット
- 遅延ロード
- メモリマップトファイルのページイン
- 必要以上の動的確保
- 大きなオブジェクトや断片化したヒープ

周期処理の本体では、**必要なメモリを先に確保して、起動時に一度触っておく** くらいでちょうどよいです。

### 3.4. タイマ分解能と電源管理

「1ms ごとに動かしたいから `Sleep(1)`」は、ほとんどの場合うまくいきません。  
Windows の待機精度は、タイマ分解能、スケジューリング、電源状態の影響を受けます。

さらに、タイマ分解能を上げる設定は、**待機精度を少し改善できる一方で、消費電力やシステム全体の挙動に副作用がある** ことも押さえておく必要があります。

### 3.5. コア移動と熱

スレッドがコア間を移動すると、キャッシュの温まり直しが発生します。  
これ自体は OS がうまく処理してくれることも多いのですが、負荷が高い環境では揺れの原因になります。

さらに、長時間回すと熱の影響も無視できません。  
**サーマルスロットリングが入ると、それまで安定していた周期が崩れる** ことがあります。

## 4. アンチパターン

### 4.1. `Sleep` 任せの周期ループ

まず典型例です。

```cpp
while (running)
{
    Sleep(1);
    Step();
}
```

これは「1ms 周期」ではなく、**だいたい 1ms 以上待ってから、そこに `Step()` の実行時間を足す** ループです。  
しかも待機オーバーシュートがそのまま累積します。

周期処理は、**相対時間でなく絶対期限** で回したほうが安定します。

### 4.2. ホットパスでブロッキング I/O

ホットパスで次をやると、後で問題になります。

- ファイル書き込み
- ネットワーク送信
- DB 書き込み
- 重いログ出力
- 同期 RPC
- `Flush` 系の処理

開発中はたまたま速く見えても、本番の揺れには耐えません。  
ホットパスでは **最小限のコピーだけして、後段へ流す** のが基本です。

### 4.3. ホットパスで確保・解放・GC

ホットパスで毎回 `new` / `malloc` / `List<T>.Add` / 文字列連結 / LINQ を使うと、いつか回収や再配置の都合が表に出ます。

GC 自体が悪いわけではありません。  
ただ、割り当ての多いコードを書けば、その影響は遅延として表面化します。 ホットパスでは、そもそも回収を呼び込まない書き方を優先したほうがよいです。

### 4.4. 無制限キュー

「遅れたらキューに積めばよい」は、一見安全そうで、実際には危険です。  
無制限キューは、**取りこぼしを見えなくして、遅延を未来へ先送りするだけ** になりがちです。

必要なのは、

- 上限
- 溢れたときの方針
- 溢れた事実の観測

です。

### 4.5. いきなり `REALTIME_PRIORITY_CLASS`

これは強い手段ですが、使い方を誤ると危険です。  
Windows のドキュメントでも、`REALTIME_PRIORITY_CLASS` は他のプロセスだけでなく **OS の重要処理より先に走り得る** とされていて、ディスクキャッシュが流れない、マウスが反応しない、といった副作用まで書かれています。

つまり、「最優先にすれば解決するだろう」という発想で最初に入れるものではありません。  
専用機で十分に挙動を理解し、必要性が明確になってから検討するべき設定です。

## 5. 設計の基本方針

### 5.1. fast path / slow path を分ける

構成の基本はこれです。

```mermaid
flowchart LR
    Device[デバイス / 高精度イベント] --> RT[fast path<br/>取得・制御・最小限のコピー]
    RT --> Ring[固定長リングバッファ]
    Ring --> Worker[slow path<br/>整形・保存・送信]
    Worker --> UI[UI / ログ / DB / ネットワーク]
    RT --> Stat[ジッタ・overrun計測]
    Stat --> Worker
```

fast path でやるのは、たとえば次だけです。

- データ取得
- 制御値計算
- 必要最小限のコピー
- タイムスタンプ
- キュー投入
- miss / overrun の記録

それ以外は slow path に落とします。

### 5.2. 固定長キューとドロップ方針を先に決める

キューは **固定長** が基本です。  
さらに、溢れたときの方針を先に決めておきます。

たとえば、

- **latest wins**  
  最新値だけ意味があるなら、古いものを捨てる
- **all data matters**  
  欠落が許されないなら、静かに遅延させず、アラートや停止にする
- **logging only**  
  ログなら古いものを落としてカウンタだけ残す

この方針が曖昧だと、本番で問題が起きたときに「何が失われたか」が分からなくなります。

### 5.3. マルチレート設計にする

全部を同じ周期で回す必要はありません。  
役割ごとに周期を分けたほうが自然です。

たとえば、

- 1kHz: 取得 / 制御
- 100Hz: 推定 / フィルタ更新
- 20Hz: UI 更新 / ログ集約

のように分けます。

UI を高い周期で更新したくなる場面はありますが、多くの場合は分けたほうがシステム全体が安定します。

### 5.4. deadline miss を観測可能にする

周期違反は、例外ではなく **運用上のメトリクス** として扱ったほうが強いです。  
最低でも次は持っておくとよいです。

- 予定開始時刻
- 実開始時刻
- 実終了時刻
- lateness
- 実行時間
- missed deadline 回数
- 連続 miss 回数
- キュー最大深さ

遅れたら隠すのではなく、数える。  
このほうが後で原因を詰めやすくなります。

## 6. 実装の基本方針

### 6.1. 優先度の基本方針

優先度の基本は、**全部を上げない** ことです。

おすすめの考え方はこうです。

- UI や通常ワーカーは普通の優先度
- 本当に時間が厳しいスレッドだけを上げる
- ログ保存や送信のような後ろ仕事は background mode へ落とす
- プロセス全体より、まず **スレッド単位** で考える

Windows のドキュメントでも、背景処理については CPU 優先度だけでなく、**resource scheduling priority** を下げる background mode を使うよう書かれています。  
つまり、保存やアップロードのような遅れてもよい仕事は、明示的に優先度を下げたほうが全体が安定します。

### 6.2. MMCSS を使う場面

音声、映像、連続ストリーミングのような「一定時間内にバッファを埋める」タイプの処理では、まず **MMCSS** を検討します。

MMCSS は、時間に敏感な処理へ CPU を優先配分しつつ、低優先度タスクを完全に止めないようにする仕組みです。  
単純に高優先度スレッドを常時走らせるより、Windows の設計に沿ったやり方です。

イメージとしてはこうです。

- 音声 / 映像 / キャプチャ / 再生系  
  → MMCSS をまず検討
- 一般的な周期制御  
  → 専用スレッド + 適切な優先度 + 計測から始める
- 何でもかんでも MMCSS  
  → 向いていないことが多い

コードの雰囲気はこんな感じです。

```cpp
DWORD taskIndex = 0;
HANDLE avrt = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);
if (!avrt)
{
    throw std::runtime_error("AvSetMmThreadCharacteristicsW failed");
}

// ここで時間に敏感なループを回す

if (!AvRevertMmThreadCharacteristics(avrt))
{
    throw std::runtime_error("AvRevertMmThreadCharacteristics failed");
}
```

「常時高優先度で回す」というより、**このスレッドは期限に敏感な処理を担当している** と OS に伝えるイメージです。

### 6.3. タイマと時計の選び方

ここは役割で分けると整理しやすいです。

#### 6.3.1. 経過時間を測る時計

経過時間の計測は、**QueryPerformanceCounter（QPC）** を使います。  
.NET なら `Stopwatch` / `Stopwatch.GetTimestamp()` です。

壁時計の時刻ではなく、「前回から何 ticks 経ったか」を測る道具として使います。  
`DateTime.Now` を周期ループの基準に持ち込むのは避けたほうがよいです。

一方で、外部ログと突き合わせるための UTC 時刻が必要なら、`GetSystemTimePreciseAsFileTime` のような壁時計系を別に持ちます。  
**経過時間用の時計** と **実時刻用の時計** を分ける、ということです。

#### 6.3.2. 待機の道具

優先順位としては、だいたい次です。

1. デバイスや API が持つイベント駆動
2. 高精度 waitable timer
3. 通常の待機 + 必要なら `timeBeginPeriod`
4. 最後の微調整だけ短い busy-spin

特に `CreateWaitableTimerEx` の **`CREATE_WAITABLE_TIMER_HIGH_RESOLUTION`** は、数ミリ秒級の短い期限で待機遅れを減らしたい場面で有力です。

#### 6.3.3. `timeBeginPeriod` の扱い

`timeBeginPeriod` は、使い方を整理しておけば役に立ちます。  
ただし、次の点は押さえておく必要があります。

- 必要な直前に呼ぶ
- 終わったら `timeEndPeriod` で戻す
- Windows 10 version 2004 以降は、昔のような完全なグローバル挙動ではない
- Windows 11 では、**ウィンドウを持つプロセスが完全に隠れる / 最小化される / 見えない / 聞こえない状態** だと、高い分解能が保証されないことがある
- 分解能を上げても **QPC の精度が上がるわけではない**
- 分解能を上げると、消費電力とシステム全体の挙動には副作用がある

つまり、`timeBeginPeriod(1)` を入れれば終わり、という話ではありません。  
必要なところにだけ、必要な時間だけ使います。

#### 6.3.4. 実用的な待ち方

周期ループでは、次のような「待機 + 短い微調整」が現実的です。

```mermaid
sequenceDiagram
    participant Loop as 制御スレッド
    participant Timer as waitable timer / device event
    participant CPU as CPU

    Loop->>Timer: 次の期限の少し手前まで待つ
    Timer-->>Loop: 起床
    Loop->>CPU: 数十〜数百マイクロ秒だけ短く spin
    Loop->>Loop: FastStep() 実行
    Loop->>Loop: next += period
```

長い busy-spin は CPU 使用率を上げやすいですが、**最後のごく短い区間だけ** なら有効です。  
長く回すのではなく、最後の調整に限定して使います。

### 6.4. メモリの扱い

ホットパスでは次を徹底したいです。

- バッファは先に確保する
- 起動時に一度触ってページを温める
- オブジェクト再利用を前提にする
- ループ中に巨大な構造を育てない
- 共有ヒープへ無計画に集めない

必要なら `VirtualLock` で **ごく小さいクリティカルな領域だけ** 固定する手もあります。  
ただしこれは乱用しないほうがよいです。 Windows のドキュメントでも、ロックしたページが増えると他の重要ページが追い出され、全体性能を悪くし得るとされています。

要するに、`VirtualLock` は補助的な手段であって、設計上の問題をまとめて解決してくれるものではありません。

### 6.5. CPU の置き方

CPU 配置は、いきなり hard pin するより、**soft affinity に近い指定から始める** ほうがうまくいくことが多いです。

候補としてはこうです。

- `SetThreadIdealProcessor`  
  まず「このあたりのコアで実行されると望ましい」と伝える
- **CPU Sets**  
  OS の電源管理と両立しやすい soft affinity として使う
- `SetThreadAffinityMask`  
  本当に必要なときだけ固定する

特に CPU Sets は、ドキュメント上でも **OS power management と両立する soft affinity** として説明されています。  
「このスレッドはこの集合のどこかで走ってくれればよい」という指定ができるので、完全固定より扱いやすいです。

一方で `SetThreadAffinityMask` のドキュメントには、**多くの場合は OS に選ばせたほうがよい** とも書かれています。  
固定すると、その分だけスケジューラの逃げ道を減らすからです。

なので順番としては、

1. まず計測する
2. 必要なら ideal processor / CPU Sets
3. それでも改善が必要なら hard affinity

がよいです。  
CPU pinning は効果がありそうに見えますが、安易に使うと単に融通が利かなくなることがあります。

### 6.6. 周期ループの擬似コード

周期ループは、相対時間ではなく **絶対期限** で回したほうが安定します。

```cpp
int64_t next = QpcNow() + periodTicks;

while (running)
{
    WaitUntil(next - wakeMarginTicks);   // event / waitable timer
    while (QpcNow() < next)
    {
        CpuRelax();                      // 最後だけ短く spin
    }

    int64_t started = QpcNow();
    FastStep();                          // no blocking, no alloc, no heavy lock
    int64_t finished = QpcNow();

    RecordTiming(next, started, finished);

    next += periodTicks;

    // 遅れたときの catch-up policy
    while (finished > next)
    {
        ++missedDeadlines;
        next += periodTicks;
    }
}
```

ポイントは 2 つです。

- `next = now + period` にしない  
  → オーバーシュートが毎回ドリフトとして積み上がるため
- 遅れたときの方針を明示する  
  → 追いつくまでスキップするのか、最新値だけ取るのか、停止するのか

「いつも間に合う前提」のコードより、**遅れたときの動きが先に決まっている** コードのほうが、本番で扱いやすいです。

### 6.7. .NET 側の注意

C# / .NET でやるなら、特に次は効きます。

- 時刻計測は `Stopwatch` / `Stopwatch.GetTimestamp()`
- ホットパスでアロケーションしない
- LINQ、文字列連結、`ToString()`、巨大なログ生成を持ち込まない
- `async/await` は slow path には便利だが、hot path には慎重に
- 起動直後の JIT や初回実行コストを甘く見ない
- 初回ウォームアップを本計測に混ぜない

C# / .NET でも十分実装できます。  
ただし、managed runtime の便利さを hot path にそのまま持ち込むと、GC や初回コストがジッタとして表に出ます。

## 7. 電源設定・OS設定の考え方

### 7.1. まず触る設定

まずはここです。

- **AC 給電で動かす**
- **[設定] > [システム] > [電源 & バッテリー] > [電源モード]** を **[最適なパフォーマンス]** 寄りにする
- 省エネルギー / battery saver 的な設定を実行中は使わない
- ノート PC のベンダー独自ユーティリティで、静音 / eco / battery 優先モードになっていないか確認する

ここは地味ですが、効果があります。  
ループを詰めても、上位の電源制御が強く効いていると結果は安定しません。

### 7.2. 電源プランの考え方

より詰めるなら、**専用の電源プラン** を用意したほうがよいです。  
普段使いと、本番実行時を分けます。

実務的には、

- 普段使い: バランス
- 本番 / 計測 / デモ: 専用プラン

が扱いやすいです。

さらに、専用機または専用時間帯なら、AC 時のみ次も検討できます。

- **最小のプロセッサの状態 = 100%**
- **最大のプロセッサの状態 = 100%**
- スリープ / 休止を実行中は無効化
- ディスプレイや周辺機器の積極的な省電力を避ける

Microsoft の電源設定ドキュメントでも、**最小のプロセッサ性能状態を 100% にすると CPU を performance 寄りに bias する** 例が示されています。  
ただし、これは熱・消費電力・ファン騒音と引き換えです。 ノート PC で常用する設定ではありません。

また、**カスタム電源プランが選ばれていると、設定アプリ側の [電源モード] が変えられないことがある** 点も押さえておきたいです。  
その場合はいったんバランス プランを選んでから調整します。

### 7.3. Process Power Throttling / EcoQoS

Windows には、プロセス単位の power throttling があります。  
省電力寄りに動かしたい処理には便利ですが、ソフトリアルタイムの本体には逆効果になることがあります。

特に見たいのは次です。

- `PROCESS_POWER_THROTTLING_EXECUTION_SPEED`
- `PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION`

ドキュメントのサンプルでも、

- `EXECUTION_SPEED` をオンにすると EcoQoS
- `EXECUTION_SPEED` をオフにすると HighQoS
- `IGNORE_TIMER_RESOLUTION` をオフにすると timer resolution request を尊重

という形が示されています。

実行時に critical process だけ HighQoS 寄りにするなら、たとえば次のようになります。

```cpp
PROCESS_POWER_THROTTLING_STATE state{};
state.Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
state.ControlMask =
    PROCESS_POWER_THROTTLING_EXECUTION_SPEED |
    PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION;
state.StateMask = 0; // HighQoS + timer resolution request を尊重

if (!SetProcessInformation(
        GetCurrentProcess(),
        ProcessPowerThrottling,
        &state,
        sizeof(state)))
{
    throw std::runtime_error("SetProcessInformation failed");
}
```

ここは、タイマ分解能や CPU throttling の影響が疑わしいときに確認したい設定です。

### 7.4. バックグラウンド負荷と運用

OS 設定だけでなく、運用も効きます。

- 重いクラウド同期
- 大量ログの圧縮
- インデックス作成
- 自動アップデート
- 常駐監視の走査
- ブラウザのタブを大量に開いた状態

このあたりが並ぶと、周期スレッドへの干渉要因が一気に増えます。

おすすめは、

- 本番時間帯は不要な常駐を減らす
- 自分の slow path は background mode に落とす
- USB / Wi-Fi / ストレージ起因が疑わしいなら、まず **ドライバ / ファームウェア更新** を見る
- 「最小化したら崩れる」「画面を消したら崩れる」もちゃんと試す

です。

特に Windows 11 のタイマ分解能の挙動を見ると、**GUI の見え方** が影響することがあるので、  
「前面表示でしか試していない」という状態は避けたいです。

### 7.5. BIOS / UEFI は最後に

BIOS / UEFI 側にも、

- 省電力プロファイル
- 静音プロファイル
- ベンダー独自の boost / eco 制御
- C-state や周波数関連の設定

があります。

ただし、ここは機種依存が強いです。  
最初から全部触るのではなく、

1. Windows 側で詰める
2. 計測する
3. 本当に BIOS / UEFI が怪しいと分かってから触る

の順がよいです。

最初から一律に C-state を切る、周波数を固定する、という進め方より、**どの設定で p99 と max がどう変わったか** を見るほうが確実です。  
効く設定もあれば、ほとんど差が出ない設定もあります。

## 8. 計測と評価

### 8.1. 何を記録するか

最低限、次は見たいです。

- 周期予定時刻
- 実開始時刻
- 実終了時刻
- lateness
- 実行時間
- missed deadline 数
- 連続 missed deadline 数
- キュー深さ
- ドロップ数
- CPU 使用率
- コア別の偏り
- DPC/ISR スパイク
- page fault
- 温度 / クロック変動

平均だけ見ても、本質はつかみにくいです。  
本番で問題になるのは、たまに出る大きな遅延です。

### 8.2. 何で見るか

道具としては、だいたい次です。

- **アプリ内計測**  
  まず自前で、period / lateness / execution time / queue depth を取る
- **ETW / WPR / WPA**  
  CPU、context switch、DPC/ISR、page fault を掘る
- **LatencyMon**  
  ドライバ起因の揺れのあたりを付ける
- **温度 / クロック監視**  
  熱の影響を見る

WPA まで行くと少し骨が折れますが、**DPC/ISR が原因なのか、単に自分の処理が重いのか** を分けるにはかなり有効です。

### 8.3. テストの作法

テストは、静かなベンチだけでは足りません。  
少なくとも次を分けて見ます。

- 起動直後のウォームアップ前
- ウォームアップ後
- 長時間連続運転
- UI 前面
- UI 最小化 / 非表示に近い状態
- AC 給電
- バッテリー駆動
- ネットワークやディスクに負荷がある状態

ベンチ環境だけで評価すると、実運用で出る問題を見落としやすくなります。  
実際に使う条件に近づけて確認しておくと、後で慌てにくくなります。

## 9. ざっくり使い分け

- **10〜20ms 級で、たまの揺れは吸収できる**  
  → fast/slow 分離、固定長キュー、通常優先度〜やや高め、イベント駆動で十分なことが多い

- **1〜5ms 級で、継続的に間に合わせたい**  
  → ホットパスの無割り当て化、専用スレッド、MMCSS または慎重な優先度調整、高精度 waitable timer、AC 給電、最適なパフォーマンス寄りの電源設定

- **1ms 未満に近づき、しかも長時間・高負荷でも外したくない**  
  → user-mode Windows 単独では厳しくなってくる。 クリティカル部分を別の場所へ逃がす設計を考える

- **GUI / ログ / 通信 / DB と全部同居**  
  → 「全部 1 プロセス 1 ループ」で抱え込まず、責務を分離する。 後段の都合が前段の期限を壊しやすくなるため

## 10. まとめ

押さえておきたい前提:

- Windows で目指すのは hard real-time の保証ではなく、遅延とジッタを小さくし、期限違反が起きても壊れない構成にすること
- 一番効果が大きいのは、優先度調整よりもホットパスの整理です

実装で効くこと:

- fast path / slow path を分ける
- 固定長キューとあふれたときの方針を先に決める
- QPC で測り、event / waitable timer で待つ
- ホットパスでは割り当て、ブロッキング I/O、重いロックを避ける

運用で効くこと:

- AC 給電で動かす
- 本番用の電源設定を分ける
- 不要なバックグラウンド負荷を減らす
- p99 / p99.9 / max と miss 回数で評価する

要するに、Windows でのソフトリアルタイムは、優先度の設定だけで決まるものではありません。  
設計、実装、計測、運用を分けて詰めていくと、かなり安定したシステムにできます。

## 11. 参考資料

- [Multimedia Class Scheduler Service](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service)
- [AvSetMmThreadCharacteristicsW function](https://learn.microsoft.com/en-us/windows/win32/api/avrt/nf-avrt-avsetmmthreadcharacteristicsw)
- [SetThreadPriority function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setthreadpriority)
- [SetPriorityClass function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass)
- [timeBeginPeriod function](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod)
- [CreateWaitableTimerExW function](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-createwaitabletimerexw)
- [Acquiring high-resolution time stamps](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)
- [GetSystemTimePreciseAsFileTime function](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getsystemtimepreciseasfiletime)
- [SetProcessInformation function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessinformation)
- [VirtualLock function](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtuallock)
- [CPU Sets](https://learn.microsoft.com/en-us/windows/win32/procthread/cpu-sets)
- [SetThreadIdealProcessor function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setthreadidealprocessor)
- [SetThreadAffinityMask function](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadaffinitymask)
- [Processor power management options](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/configure-processor-power-management-options)
- [Windows PCの電源モードを変更する](https://support.microsoft.com/ja-jp/windows/windows-pc%E3%81%AE%E9%9B%BB%E6%BA%90%E3%83%A2%E3%83%BC%E3%83%89%E3%82%92%E5%A4%89%E6%9B%B4%E3%81%99%E3%82%8B-c2aff038-22c9-f46d-5ca0-78696fdf2de8)
- [Windows で PC のパフォーマンスを向上させるためのヒント](https://support.microsoft.com/ja-jp/windows/windows-%E3%81%A7-pc-%E3%81%AE%E3%83%91%E3%83%95%E3%82%A9%E3%83%BC%E3%83%9E%E3%83%B3%E3%82%B9%E3%82%92%E5%90%91%E4%B8%8A%E3%81%95%E3%81%9B%E3%82%8B%E3%81%9F%E3%82%81%E3%81%AE%E3%83%92%E3%83%B3%E3%83%88-b3b3ef5b-5953-fb6a-2528-4bbed82fba96)
- [CPU の分析 (WPA / WPT)](https://learn.microsoft.com/ja-jp/windows-hardware/test/wpt/cpu-analysis)
- [Using the Windows Performance Toolkit (WPT) with WDF](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/using-the-windows-performance-toolkit--wpt--with-wdf)
