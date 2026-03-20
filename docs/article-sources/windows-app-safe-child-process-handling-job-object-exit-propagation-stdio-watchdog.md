---
title: "Windows アプリで子プロセスを安全に扱う方法 - Job Object、終了伝播、標準入出力、watchdog のベストプラクティス"
date: 2026-03-20T10:00:00+09:00
author: "小村 豪"
tags:
  - Windows
  - Process
  - Job Object
  - IPC
  - C++
  - C#
  - .NET
description: "Windows アプリで子プロセスを安全に扱うには、起動 API よりもプロセス木の所有権と終了手順の設計が重要です。Job Object、終了伝播、標準入出力、watchdog を、GUI / console / worker の違いまで含めて整理します。"
---

変換ツール、アップデータ、解析ワーカー、外部 CLI、PowerShell、ffmpeg、社内ユーティリティ。  
Windows アプリは、思っている以上に簡単に子プロセスへ依存します。

ただ、事故るのは「起動できたかどうか」ではありません。

- 親が落ちたのに子だけ残る
- 孫プロセスだけが生き残る
- `stdout` / `stderr` が詰まって `WaitForExit` が返らない
- watchdog が監視対象と一緒に死ぬ
- `Kill(entireProcessTree: true)` で終わったつもりが、観測だけ先に終わる

Windows で子プロセスを安全に扱うコツは、**起動 API を選ぶこと** ではなく、  
**プロセス木の所有者を決め、終了手順と I/O を設計すること** です。

この記事では、Job Object、終了伝播、標準入出力、watchdog を一枚の設計として整理します。

## 目次

1. まず結論
2. 何が危ないのか
3. 仕組みの役割を混ぜない
4. Job Object を基準にする
5. 終了伝播を protocol と timeout で設計する
6. 標準入出力を詰まらせない
7. watchdog は「外」に置く
8. 典型パターン別の推奨構成
9. やってはいけないこと
10. まとめ
11. 参考資料

## 1. まず結論

先に、実務でいちばん効くところだけ並べます。

- **親の生死と子プロセス木の寿命を結びつけたいなら、基準点は Job Object** です。`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` がまず土台になります。[^1][^2]
- **console への終了依頼** と **プロセス木の回収** は別です。前者は process group と `GenerateConsoleCtrlEvent`、後者は Job Object です。[^1][^11]
- **起動時点から Job に入れたい** なら、`STARTUPINFOEX` と `PROC_THREAD_ATTRIBUTE_JOB_LIST` を使う設計が素直です。同じ発想で、継承 handle も `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` で絞るほうが安全です。[^3][^4]
- **標準出力 / 標準エラーは並列に吸い上げる** のが基本です。片方を `ReadToEnd` してからもう片方、は詰まりやすいです。[^5][^7]
- **`stdin` を使うなら、書き終えたら close して EOF を伝える** ところまで設計します。EOF が来ないと子が待ち続けます。[^5][^6]
- **watchdog は監視対象の Job の外に置く** ほうが安全です。同じ Job に入れると、再起動役まで一緒に落ちます。[^2]
- **`.NET` の `Kill(entireProcessTree: true)` は便利ですが、Windows の tree lifecycle 管理の土台そのものではありません**。`WaitForExit` / `HasExited` は descendant 全体の終了完了までは反映しません。[^8]

## 2. 何が危ないのか

子プロセス起動の実装は、最初はだいたい 10 行前後で書けます。  
でも事故るのは、その 10 行の外側です。

- 親が落ちたあと、子や孫が残り続ける
- helper がさらに helper を起動して、直下の子だけ待って満足してしまう
- `stdout` / `stderr` の片側が詰まって、親も子も待ち合う
- UI thread で待機して、画面も COM も固まる
- watchdog が監視対象と同じ運命共同体になっていて、異常時に一緒に落ちる

ここで大事なのは、**「子プロセス管理」は 1 つの API の話ではない** という点です。

実務では、少なくとも次の 4 つを分けて考えたほうが整理しやすいです。

1. **プロセス木を誰が所有するか**
2. **どうやって協調終了を依頼するか**
3. **標準入出力をどう流すか**
4. **異常終了とハングをどう監視するか**

この 4 つを分けずに、「とりあえず `Process.Start` した」「とりあえず `CreateProcess` した」で終えると、後で lifecycle の責任が見えなくなります。

## 3. 仕組みの役割を混ぜない

ここはかなり重要です。  
**process handle / process group / Job Object は、似て見えて役割が違います。**

| 仕組み | 主な役割 | 向いている場面 | それだけでは足りないこと |
|---|---|---|---|
| プロセス handle | 1 プロセスの終了待ち、exit code 取得 | 単発ツールの完了待ち | 孫プロセスの回収 |
| process group | console への Ctrl+Break 伝播 | console child の協調終了 | 親クラッシュ時の cleanup、GUI 子プロセス |
| Job Object | プロセス木の束ね、制限、まとめて終了 | worker tree、updater、helper chain | アプリ固有の「保存してから閉じる」 |

process group は `CREATE_NEW_PROCESS_GROUP` と `GenerateConsoleCtrlEvent` の世界です。  
**console signal をどこへ送るか** を決める仕組みであって、**親が死んだら木ごと片づける** ための仕組みではありません。[^11]

一方で Job Object は、**プロセス群を 1 単位で管理する** ための Windows の仕組みです。  
子プロセスの tree cleanup を Windows 側のモデルで扱いたいなら、こちらが本命です。[^1]

## 4. Job Object を基準にする

Job Object のいちばん強い点は、**「誰の子か」ではなく「どの Job に属するか」** で process tree を束ねられることです。  
Job に入ったプロセスが `CreateProcess` で作る子は、デフォルトでその Job に入ります。つまり、親 -> 子 -> 孫という chain を、アプリ側で PID 追跡しなくてもある程度まとめて扱えます。[^1]

さらに、`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` を付けると、**最後の job handle が閉じられたとき** に、Job に関連付けられた全プロセスが終了します。[^2]

### 4.1 まず押さえたい 4 つ

#### 1. 親終了で木ごと片づけたいなら `KILL_ON_JOB_CLOSE` を基準にする

これは Windows アプリで helper / worker を扱うときの土台です。  
`TerminateJobObject` を明示的に呼ぶ設計でもよいですが、**親の異常終了や例外脱出まで含めて cleanup を親の寿命へ寄せたい** なら、`KILL_ON_JOB_CLOSE` が分かりやすいです。[^1][^2]

#### 2. `BREAKAWAY` を軽く付けない

Job に入ったプロセスが作る子は、デフォルトで同じ Job に入ります。  
これを逃がすのが `JOB_OBJECT_LIMIT_BREAKAWAY_OK` や `JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK` です。[^1][^2]

この 2 つは便利そうに見えますが、**「cleanup できるつもりだった木から一部が抜ける」** 原因にもなります。  
意図がない限り、breakaway は付けないほうが事故率が下がります。

#### 3. 起動時点から Job に入れたいなら `PROC_THREAD_ATTRIBUTE_JOB_LIST`

`AssignProcessToJobObject` で後から結びつける設計でも動きます。  
ただ、**起動直後から Job 所属を前提にしたい** 場面では、`STARTUPINFOEX` と `PROC_THREAD_ATTRIBUTE_JOB_LIST` を使って、プロセス作成時に Job を指定するほうが筋がよいです。[^3]

特に、

- 子が起動直後にさらに子を作る
- 起動直後から監視・制限を効かせたい
- 「一瞬だけ Job の外」が嫌

というケースでは、この発想が効きます。

#### 4. job handle の所有者を曖昧にしない

`KILL_ON_JOB_CLOSE` は **最後の handle が閉じたとき** に効きます。[^1][^2]

つまり逆に言うと、

- job handle を別プロセスへ複製した
- 監視用 helper が job handle を持っている
- 意図せず継承させた

といった状態だと、親が死んでも **まだ last handle ではない** ので、想定どおりに cleanup されません。

実務ではここがかなり重要です。  
**「誰が job handle の最終所有者か」** を決めておかないと、終了責任があいまいになります。

### 4.2 Job Object は observability にも使えるが、通知は万能ではない

Job Object には I/O completion port を関連付けて通知を受ける仕組みがあります。  
ただし、Microsoft Learn でも、`JobObjectNotificationLimitInformation` に関する通知を除いて、completion port への通知配信は guaranteed ではないと明記されています。[^17]

なので completion port は、

- 監視
- 集計
- ログ
- メトリクス

には便利ですが、**「通知が来なかったから起きていない」** という前提で correctness を組むのは危険です。

## 5. 終了伝播を protocol と timeout で設計する

子プロセスの終了は、**1 発の kill API で終わる話ではありません**。

いちばん事故りにくいのは、だいたい次の 3 段階です。

1. **協調終了を依頼する**
2. **短い timeout で待つ**
3. **最後に Job ごと強制終了する**

この順番にしておくと、

- 正常な終了経路は保つ
- でもハング時は回収できる

というバランスが取りやすくなります。

### 5.1 GUI child

GUI を持つ子プロセスなら、`.NET` では `CloseMainWindow` が「メインウィンドウへ close message を送る」操作になります。  
ただしこれは **終了要求** であって、強制終了ではありません。モーダルダイアログ表示中や、アプリ側が拒否する設計なら、そのままでは終わりません。[^9]

なので GUI child は、

- まず `CloseMainWindow` / `WM_CLOSE` 相当
- 一定時間待つ
- だめなら Job ごと kill

という流れにしておくのが実務では素直です。

### 5.2 Console child

Console child では、GUI の close message は使えません。  
このときは **process group と console signal** を使います。

`CREATE_NEW_PROCESS_GROUP` で子を新しい process group の root として起動すると、その group へ `GenerateConsoleCtrlEvent` で `CTRL_BREAK_EVENT` を送れます。[^11]

ここで見落としやすい点があります。

- `CTRL_C_EVENT` は **特定の process group に限定できません**
- signal を受け取れるのは **呼び出し側と同じ console を共有している** process だけです
- `CREATE_NEW_PROCESS_GROUP` を指定すると、その group では `CTRL+C` が無効になります[^11]

つまり console child の協調終了は、

- process group を作る
- 共有 console 条件を満たす
- `CTRL_BREAK_EVENT` を使う

まで含めて初めて設計になります。

### 5.3 Worker / headless child

長時間 worker や headless child は、GUI でも console でもないことが多いです。  
この場合は、**子プロセス専用の終了 protocol** を持ったほうが安全です。

たとえば、

- `stdin` に `quit\n` を送る
- named pipe / socket / RPC で shutdown command を送る
- event object で停止要求を伝える

のような形です。

Windows 的には Job Object が tree cleanup を担い、  
アプリ的には named pipe や `stdin` が **「保存して閉じる」** を担う、という分担がきれいです。

### 5.4 強制終了の見方

`.NET` の `Process.Kill()` は非同期です。呼んだ直後に完全終了とは限らないので、その後に `WaitForExit()` で待つ、というのが docs に沿った使い方です。[^8]

ただし `Kill(entireProcessTree: true)` でも、`WaitForExit` と `HasExited` は descendant 全体の終了完了までは反映しません。  
「root は終わったが孫はまだ後始末中」という状態で、観測だけ先に終わったように見えることがあります。[^8]

なので、**Windows 専用で tree 全体の cleanup を責任持って扱う** なら、  
`Kill(entireProcessTree: true)` を中心に据えるより、**Job Object を基準にしたほうが設計がぶれません**。

### 5.5 exit code の扱い

`GetExitCodeProcess` の `STILL_ACTIVE` は 259 です。  
Microsoft Learn でも、アプリケーションは 259 を自前の exit code に使うべきではないと書かれています。  
これを普通の失敗コードとして返すと、まだ実行中と誤認されて無限待ちに入る原因になります。[^16]

## 6. 標準入出力を詰まらせない

子プロセス周りでいちばん多い不具合の 1 つが、`stdout` / `stderr` の詰まりです。  
ここは「読めばいい」ではなく、**継承・EOF・並列 drain** まで見たほうが安全です。

### 6.1 継承は「必要な handle だけ」にする

Win32 の `CreateProcess` で `bInheritHandles=TRUE` にすると、**その時点で inheritable な handle が全部** 子へ渡ります。  
Microsoft Learn でも、これはマルチスレッドで複数プロセスを起動するアプリには problematic だと説明されていて、`PROC_THREAD_ATTRIBUTE_HANDLE_LIST` で継承 handle を限定する方法が案内されています。[^3][^4]

これは実務上かなり効きます。

- pipe handle が意図せず残る
- event / mutex / file handle が漏れる
- 「誰が持っているから EOF が来ないのか」が分からなくなる

こういう事故を減らしたいなら、**継承は whitelist 方式** に寄せたほうがよいです。

### 6.2 Win32 の標準入出力リダイレクトの基本

Win32 で標準入出力を子へ渡すなら、

- pipe handle を inheritable に作る
- `STARTUPINFO` の `STARTF_USESTDHANDLES` を使う
- 子へ渡したくない pipe の反対側は継承不可にする

というのが基本です。[^4][^5]

親が `stdout` を読む側なら、**親は自分側に残った write end をすぐ閉じる** 必要があります。  
これを閉じないと、read 側が EOF を観測できません。  
同様に、`stdin` を渡すときは、子が write end を継承してしまうと child 側の `ReadFile` が EOF を見られなくなります。[^6]

ここは本当に大事です。  
**「使わない pipe end をすぐ閉じる」** は、pipe I/O の基本作法です。

### 6.3 匿名 pipe は byte stream である

匿名 pipe は message queue ではなく、**byte stream** です。  
親が読む側から見ると、「何回 Write されたか」はそのまま残りません。境界が必要なら、行終端や length prefix などの protocol が要ります。[^6]

「とりあえず JSON を 1 回書いて終わり」ならまだ事故りにくいですが、

- 進捗ログ
- コマンド応答
- 複数レコード

のように続けて流すなら、**どこが 1 メッセージの終わりか** を先に決めたほうが安全です。

### 6.4 `stdout` / `stderr` は並列に drain する

.NET の docs でもかなりはっきり書かれている通り、**片方だけ `ReadToEnd()` してから `WaitForExit()` する**、あるいは **`stdout` を全部読んでから `stderr` を読む** という順序は deadlock を作りやすいです。[^7]

典型的な詰まり方はこれです。

1. 子が `stderr` を大量に書く
2. `stderr` pipe がいっぱいになる
3. 子は次の write で詰まる
4. 親は `stdout` だけ読んでいて `stderr` を読まない
5. 親は `WaitForExit()` を待つ
6. お互い待ち合う

なので、実務では次のどちらかに寄せたほうが安全です。

- `stdout` / `stderr` をそれぞれ別 reader で並列に drain する
- 少なくとも片方は async read にする

.NET でも `BeginErrorReadLine()` などの非同期読みによる回避例が用意されています。  
また、async で受けた出力を最後まで取り切るために `WaitForExit()` を呼ぶ必要があることも docs に書かれています。[^7]

### 6.5 `stdin` を使うなら EOF まで含めて設計する

`stdin` を command channel として使うのは悪くありません。  
ただし、

- 何を送ったら終了要求か
- いつ flush するか
- いつ close して EOF を伝えるか

まで決めないと、子が「まだ来るかも」と待ち続けます。

### 6.6 .NET 側の前提

`.NET` で `StandardOutput` / `StandardError` を読むには、`UseShellExecute = false` と各 redirect プロパティが必要です。[^12]

また、`Exited` event を使うなら `EnableRaisingEvents = true` が要ります。[^10]

この 2 つは細かいですが、トラブルシュートではかなり頻出です。

## 7. watchdog は「外」に置く

watchdog という言葉は広いですが、実務では少なくとも 2 種類に分けたほうが混乱しません。

1. **exit watchdog**  
   - プロセスが落ちたかどうかを見る
2. **hang watchdog**  
   - 生きてはいるが、仕事が止まっていないかを見る

この 2 つは、観測方法が違います。

### 7.1 exit watchdog は polling しない

プロセスは終了すると signaled 状態になります。  
だから exit 監視は、本来 polling loop で `HasExited` を 100ms ごとに見る必要がありません。[^15]

Win32 なら、

- `WaitForSingleObject`
- `WaitForMultipleObjects`
- `RegisterWaitForSingleObject`
- `SetThreadpoolWait`

が正攻法です。[^14][^15]

特に複数 child を監視するなら、`WaitForMultipleObjects` を素朴に増やしていくより、Microsoft Learn が案内しているように thread pool wait 系を使うほうが効率的です。  
`MAXIMUM_WAIT_OBJECTS` を超える handle を扱う場面でも、この発想が使えます。[^14]

また、`RegisterWaitForSingleObject` を使うなら、

- 待機中に handle を閉じない
- 完了後に wait 登録を解除する
- terminated process のように signaled のまま残る object では one-shot 化する

という lifetime 設計も必要です。[^14][^15]

.NET でも発想は同じで、`Exited` event など wait ベースで監視し、**timer polling を主役にしない** ほうが素直です。[^10]

### 7.2 UI thread で無限待機しない

Windows アプリで見落としやすいのがここです。  
`WaitForSingleObject(INFINITE)` は便利ですが、Microsoft Learn でも、window を持つ thread で無限 wait すると deadlock を起こし得るので、`MsgWaitForMultipleObjects` 系を使うべきだと書かれています。[^13]

つまり、

- UI thread
- COM apartment thread
- message pump を持つ thread

で child exit を待つなら、**待機の置き場所** を先に考えたほうが安全です。

### 7.3 hang watchdog は heartbeat が要る

exit watchdog は process handle で十分です。  
でも hang watchdog は違います。

- CPU 100% で固まっている
- deadlock している
- event loop は生きているが進捗がない
- 入力待ちで止まっている

こういう状態は、「プロセスが生きているか」だけでは判定できません。

なので hang まで見たいなら、

- heartbeat
- progress sequence
- last successful work timestamp
- named pipe / RPC での health probe

のような **アプリ層の生存確認** が要ります。

Job Object や process handle がくれるのは **OS レベルの生死** であって、**仕事が進んでいるか** までは教えてくれません。

### 7.4 再起動役は監視対象の外に置く

これはかなり重要です。

「worker が落ちたら自動再起動したい」という要件では、watchdog 自体が worker と同じ Job の中にいると、障害時に一緒に消えます。  
再起動したい側は、**監視対象の外** に置く必要があります。

実務でよくあるのは次の 2 パターンです。

- **親アプリが一時的に helper を起動するだけ**  
  - watchdog は不要  
  - 親が Job を持ち、親終了で helper tree を回収
- **長時間 worker を常駐させ、落ちたら再起動したい**  
  - 外部の watchdog process / service が worker generation ごとに Job を作る  
  - old worker tree を Job ごと止め、新しい generation を作り直す

後者では、**worker tree と restart authority を分離する** ほうが設計が安定します。

### 7.5 restart policy は budget で持つ

watchdog を入れると、次は crash loop が始まります。

- 即再起動
- また即落ちる
- ログだけ大量に出る
- ユーザーから見ると「なんか重い」

これを避けるには、

- backoff
- 一定時間内の restart 回数上限
- 連続失敗時は停止して通知

という **restart budget** を持ったほうがよいです。

ここは Windows API というより運用設計ですが、watchdog を入れるならほぼ必須です。

## 8. 典型パターン別の推奨構成

ここまでを、実務でよくある構成に落とすとこうです。

| 場面 | 推奨構成 |
|---|---|
| デスクトップアプリが単発の CLI helper を起動する | 1 起動 = 1 Job。`KILL_ON_JOB_CLOSE` を付け、`stdout` / `stderr` を並列 drain。キャンセル時は協調終了 → timeout → Job kill |
| helper がさらに孫プロセスを起動する | Job Object を前提にし、breakaway を許さない。起動時から所属を固めたいなら `PROC_THREAD_ATTRIBUTE_JOB_LIST` |
| service / watchdog が長時間 worker tree を監視する | watchdog は外部 process / service。worker generation ごとに Job を作り、exit handle + heartbeat で監視。再起動は budget つき |
| console tool を丁寧に止めたい | `CREATE_NEW_PROCESS_GROUP` で起動し、`CTRL_BREAK_EVENT` で協調終了。その後 timeout で Job kill |
| GUI helper を閉じたい | `CloseMainWindow` / `WM_CLOSE` 相当 → timeout → Job kill |
| 多数の子プロセスを監視したい | blocking thread を増やすより `RegisterWaitForSingleObject` / `SetThreadpoolWait` を使う |

この表でいちばん大事なのは、**「graceful shutdown の仕組み」と「cleanup の仕組み」を分ける** ことです。

- graceful shutdown  
  - `CloseMainWindow`  
  - `CTRL_BREAK_EVENT`  
  - `stdin` / named pipe / RPC の shutdown command
- cleanup  
  - `TerminateJobObject`  
  - `KILL_ON_JOB_CLOSE`

この 2 つを分けておくと、設計がかなり見通しやすくなります。

## 9. やってはいけないこと

最後に、実務でかなり事故りやすいものをまとめます。

- **`Kill(entireProcessTree: true)` だけで tree lifecycle が解けたと思う**  
  - .NET 側の観測は descendant 完了まで保証しません。[^8]
- **`bInheritHandles=TRUE` のまま全部継承する**  
  - pipe / event / file handle 漏れの温床です。[^3][^4]
- **`stdout` を全部読んでから `stderr` を読む**  
  - 詰まりやすいです。[^7]
- **pipe の未使用 end を閉じない**  
  - EOF が来ず、永遠に待つことがあります。[^6]
- **UI thread で `WaitForSingleObject(INFINITE)` する**  
  - message pump が止まりやすいです。[^13]
- **watchdog を監視対象と同じ Job に入れる**  
  - 再起動役も一緒に消えます。
- **259 を普通の exit code に使う**  
  - `STILL_ACTIVE` と衝突します。[^16]
- **Job completion port の通知を唯一の真実にする**  
  - 一部を除き delivery guaranteed ではありません。[^17]

## 10. まとめ

Windows アプリで子プロセスを安全に扱うとき、いちばん効くのは次の整理です。

> **誰が process tree を所有するか**  
> **どうやって終了要求を伝えるか**  
> **標準入出力をどう流し切るか**  
> **watchdog をどこへ置くか**

この 4 つを先に決める。

そのうえで、かなり雑に言うと次です。

- **tree cleanup の基準点は Job Object**
- **graceful shutdown は GUI / console / worker で分ける**
- **stdio は並列 drain と EOF まで含めて設計する**
- **watchdog は監視対象の外に置き、polling ではなく wait handle で監視する**

`CreateProcess` や `Process.Start` 自体は入口にすぎません。  
本当に事故率に効くのは、**終了責任の所在** と **I/O の流し切り** です。

外部ツール実行が多い Windows アプリほど、  
「起動できた」より先の設計で差が出ます。

## 11. 参考資料

- Microsoft Learn, [Job Objects - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
- Microsoft Learn, [JOBOBJECT_BASIC_LIMIT_INFORMATION (winnt.h)](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_limit_information)
- Microsoft Learn, [UpdateProcThreadAttribute function (processthreadsapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute)
- Microsoft Learn, [InitializeProcThreadAttributeList function (processthreadsapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-initializeprocthreadattributelist)
- Microsoft Learn, [Inheritance (Processes and Threads)](https://learn.microsoft.com/en-us/windows/win32/procthread/inheritance)
- Microsoft Learn, [CreateProcessW function (processthreadsapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)
- Microsoft Learn, [Creating a Child Process with Redirected Input and Output](https://learn.microsoft.com/en-us/windows/win32/procthread/creating-a-child-process-with-redirected-input-and-output)
- Microsoft Learn, [Pipe Handle Inheritance](https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-handle-inheritance)
- Microsoft Learn, [PeekNamedPipe function](https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-peeknamedpipe)
- Microsoft Learn, [ProcessStartInfo.RedirectStandardOutput Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.redirectstandardoutput?view=net-10.0)
- Microsoft Learn, [ProcessStartInfo.RedirectStandardError Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.redirectstandarderror?view=net-10.0)
- Microsoft Learn, [Process.StandardOutput Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.standardoutput?view=net-10.0)
- Microsoft Learn, [ProcessStartInfo.UseShellExecute Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.useshellexecute?view=net-10.0)
- Microsoft Learn, [Process.EnableRaisingEvents Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.enableraisingevents?view=net-10.0)
- Microsoft Learn, [Process.Exited Event](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.exited?view=net-10.0)
- Microsoft Learn, [Process.CloseMainWindow Method](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.closemainwindow?view=net-10.0)
- Microsoft Learn, [Process.Kill Method](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.kill?view=net-10.0)
- Microsoft Learn, [GenerateConsoleCtrlEvent function](https://learn.microsoft.com/en-us/windows/console/generateconsolectrlevent)
- Microsoft Learn, [Process Creation Flags](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags)
- Microsoft Learn, [Terminating a Process](https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-process)
- Microsoft Learn, [GetExitCodeProcess function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getexitcodeprocess)
- Microsoft Learn, [WaitForSingleObject function](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject)
- Microsoft Learn, [RegisterWaitForSingleObject function](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-registerwaitforsingleobject)
- Microsoft Learn, [WaitForMultipleObjects function](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitformultipleobjects)
- Microsoft Learn, [JOBOBJECT_ASSOCIATE_COMPLETION_PORT (winnt.h)](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_associate_completion_port)

[^1]: Microsoft Learn, [Job Objects - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
[^2]: Microsoft Learn, [JOBOBJECT_BASIC_LIMIT_INFORMATION (winnt.h)](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_limit_information)
[^3]: Microsoft Learn, [UpdateProcThreadAttribute function (processthreadsapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute) / [InitializeProcThreadAttributeList function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-initializeprocthreadattributelist)
[^4]: Microsoft Learn, [Inheritance (Processes and Threads)](https://learn.microsoft.com/en-us/windows/win32/procthread/inheritance) / [CreateProcessW function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)
[^5]: Microsoft Learn, [Creating a Child Process with Redirected Input and Output](https://learn.microsoft.com/en-us/windows/win32/procthread/creating-a-child-process-with-redirected-input-and-output)
[^6]: Microsoft Learn, [Pipe Handle Inheritance](https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-handle-inheritance) / [PeekNamedPipe function](https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-peeknamedpipe)
[^7]: Microsoft Learn, [ProcessStartInfo.RedirectStandardOutput Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.redirectstandardoutput?view=net-10.0) / [ProcessStartInfo.RedirectStandardError Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.redirectstandarderror?view=net-10.0)
[^8]: Microsoft Learn, [Process.Kill Method](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.kill?view=net-10.0)
[^9]: Microsoft Learn, [Process.CloseMainWindow Method](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.closemainwindow?view=net-10.0)
[^10]: Microsoft Learn, [Process.EnableRaisingEvents Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.enableraisingevents?view=net-10.0) / [Process.Exited Event](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.exited?view=net-10.0)
[^11]: Microsoft Learn, [GenerateConsoleCtrlEvent function](https://learn.microsoft.com/en-us/windows/console/generateconsolectrlevent) / [Process Creation Flags](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags)
[^12]: Microsoft Learn, [Process.StandardOutput Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.standardoutput?view=net-10.0) / [ProcessStartInfo.UseShellExecute Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.useshellexecute?view=net-10.0)
[^13]: Microsoft Learn, [WaitForSingleObject function](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject)
[^14]: Microsoft Learn, [RegisterWaitForSingleObject function](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-registerwaitforsingleobject) / [WaitForMultipleObjects function](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitformultipleobjects)
[^15]: Microsoft Learn, [Terminating a Process](https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-process)
[^16]: Microsoft Learn, [GetExitCodeProcess function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getexitcodeprocess)
[^17]: Microsoft Learn, [JOBOBJECT_ASSOCIATE_COMPLETION_PORT (winnt.h)](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_associate_completion_port)
