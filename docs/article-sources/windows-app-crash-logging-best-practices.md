---
title: "Windows アプリがプログラムミスによる例外で落ちても確実にログを残すには - in-process に賭けない設計と WER / 最終ログ / 監視プロセスのベストプラクティス"
date: "2026-03-18 10:00:00 +0900"
slug: "windows-app-crash-logging-best-practices"
description: "Windows アプリが想定外例外やプログラムミスで落ちても、あとから原因を追えるだけの証跡を残すために、通常ログ、最終クラッシュマーカー、WER LocalDumps、監視プロセスをどう組み合わせるべきかを整理します。"
tags:
  - Windows開発
  - 例外処理
  - ログ
  - WER
  - クラッシュダンプ
  - 不具合調査
---

Windows アプリの不具合調査で一番つらいのは、**落ちたことだけは分かるのに、なぜ落ちたかが残っていない** 状態です。

特に次のような案件では、この問題がかなり重くなります。

- 顧客環境でしか落ちない
- 長時間運転の末にだけ落ちる
- WPF / WinForms / Windows サービス / 常駐アプリで、再現率が低い
- COM、P/Invoke、native DLL、vendor SDK が絡む
- 「例外メッセージだけ」は取れているが、直前の文脈がない

ただし、最初に正直に言うと、**落ちる側のプロセスだけで「必ず」ログを残すことはできません**。  
スタック破損、メモリ破壊、fast fail、強制終了、電源断まで含めると、in-process の最後のログは本質的に *best effort* です。

実務で目指すべきなのは、**落ちるプロセスの中だけに期待しない構成** にすることです。  
つまり、

1. 通常時の時系列ログ
2. 落ちる瞬間の最終クラッシュマーカー
3. OS または別プロセス側で残すクラッシュ証跡

の 3 層で考えます。

この記事では、Windows デスクトップアプリ、常駐アプリ、Windows サービス、装置連携ツールを前提に、**プログラムミスによる例外で落ちても、調査可能性を失わないためのベストプラクティス** を整理します。

## 1. まず結論

先に結論だけ並べます。

- **「最後のログ」を 1 本の in-process ハンドラに賭けない** のが最重要です。
- 実務で一番無難なのは、**通常ログ + 最終クラッシュマーカー + WER LocalDumps** の組み合わせです。
- 長時間運転、装置連携、プラグイン、native SDK 混在なら、**監視プロセス（watchdog / launcher / service）を足す** とかなり強くなります。
- クラッシュハンドラでは、**重い処理をしない** のが鉄則です。圧縮、HTTP 送信、DI 解決、UI ダイアログ、複雑な JSON 生成は外します。
- **クラッシュ時はローカルへ短く残すだけ** にして、圧縮・アップロード・通知は **次回起動後か別プロセス** に回します。
- WinForms の `ThreadException` や WPF の `DispatcherUnhandledException` を使って **見かけ上延命する設計は、プログラムミス相手では危険** です。
- .NET でも native でも、**破損状態を疑う例外は「回復」より「記録して終了」** を基本にしたほうが安全です。
- ダンプを取るなら、**PDB と配布バイナリの保管** を同時にやらないと後で読めません。

要するに、ベストプラクティスは  
**「落ちる瞬間に全部やろうとしない。落ちる前・落ちる瞬間・落ちた後で役割分担する」**  
です。

## 2. なぜ in-process だけでは「確実」にできないのか

ここを曖昧にすると、設計がぶれます。

### 2.1 落ちたスレッドの文脈そのものが壊れていることがある

未処理例外のフックやトップレベル例外フィルタは、**壊れた側のスレッド文脈で動く** ことがあります。  
この時点で、

- スタックがもう危ない
- ヒープ破壊で追加確保が危ない
- 例外発生時に取っていたロックのせいで待機すると止まる
- logger 自体が依存しているオブジェクトが既に壊れている

ということが普通にあります。

なので、**最後のハンドラは「何でもできる場所」ではなく、「やれることがかなり少ない場所」** と見たほうが安全です。

### 2.2 fast fail や破損状態例外は「最小限の in-process 動作」前提

メモリ破壊や致命的な状態では、通常の例外処理に期待しないほうがよいです。  
特に native 側の `__fastfail` 系や、破損状態を疑う異常は、**「できるだけ少ないオーバーヘッドで即終了する」** 方向で設計されています。

つまり、**最後の in-process ログは書けたらラッキー、主証跡は OS / 別プロセス側** という考え方が自然です。

### 2.3 .NET の未処理例外イベントも「重い回復処理」の場ではない

`.NET` の `AppDomain.UnhandledException` は便利ですが、  
ここでやってよいのは **短い記録** までと考えたほうがよいです。

- 例外発生時に保持していたロックの影響を受けうる
- 破損状態例外まで何でも安全に取れるわけではない
- ここで継続方針を無理に作ると、半壊れ状態で延命しやすい

要するに、**「未処理例外イベント = 最後の通知」** であって、**「安全な回復地点」ではない** です。

## 3. 推奨アーキテクチャ - crash-time と after-restart を分ける

一番整理しやすいのは、**クラッシュ時にやること** と **再起動後にやること** を分ける方法です。

| フェーズ | 目的 | どこで動かすか | やること |
| --- | --- | --- | --- |
| 通常時 | 時系列を残す | アプリ内 | 構造化ログ、heartbeat、境界イベント |
| クラッシュ時 | 最低限の証跡を落とす | アプリ内 + OS | 最終クラッシュマーカー、WER ダンプ |
| 終了直後 | unexpected exit を検知する | 別プロセス | exit code 記録、再起動判断、通知 |
| 次回起動後 | 重い後処理をする | 新しい健全なプロセス | 圧縮、アップロード、ユーザー通知、古いログ整理 |

この分け方にすると、設計がかなり安定します。

### 3.1 最小構成

小さめの業務ツールや社内向け WPF / WinForms なら、まずは次で十分なことが多いです。

- 通常ログ: ローカルの append-only ファイル
- 最終クラッシュマーカー: 専用の短いファイル
- ダンプ: WER LocalDumps
- 次回起動時: 「前回異常終了しました。診断情報があります」を出す

### 3.2 強めの構成

次のような要件なら、1 段強くしたほうがよいです。

- 24/7 運転
- 装置制御、監視、常駐
- COM / P/Invoke / native SDK が多い
- 子プロセス、プラグイン、スクリプト実行がある
- 顧客環境で「止まりっぱなし」が許されない

この場合は、

- worker プロセス: 本体処理
- launcher / watchdog / service: 起動監視、exit 記録、再起動
- WER LocalDumps: worker 側
- 次回起動または watchdog: 診断情報回収

に分けると、かなり実務向きになります。

## 4. 通常ログのベストプラクティス

クラッシュ時の最後の 1 行だけで戦おうとすると、だいたい負けます。  
本当に効くのは、**直前までの通常ログ** です。

### 4.1 ログは「人間向け文章」より「あとで相関できる情報」

通常ログには最低でも次を入れます。

- UTC タイムスタンプ
- プロセス開始からの経過時間
- PID / TID
- アプリ名、バージョン、ビルド番号、コミット識別子
- セッション ID
- 操作 ID / ジョブ ID / 相関 ID
- モジュール名 / 画面名 / ワーカー名
- 直前の外部作用
  - ファイル書き込み
  - DB 更新
  - 装置コマンド送信
  - 通信要求
- 例外型、HRESULT / Win32 エラー / 例外コード
- 主要な入力パラメータの要約
- 機密を含まない範囲での対象 ID

おすすめは、**1 行 1 イベントの JSON Lines か key=value 形式** です。

人間向けに長文を残すより、  
**「あとで 3 ファイルを突き合わせられる」** ことのほうが重要です。

### 4.2 クリティカルイベントは同期的に残す

通常ログを全部同期書き込みにすると重くなります。  
ただし、全部を非同期バッファ任せにすると、落ちた瞬間にまとめて消えます。

なので、実務では次の分け方が扱いやすいです。

- `Information` の細かいイベント: バッファしてよい
- `Warning` 以上: 早めに flush
- 重要な境界イベント: **同期的に残す**
  - ProcessStart
  - ConfigLoaded
  - WorkerStarted
  - ExternalCommandSent
  - TransactionCommitted
  - RecoveryStarted
  - FatalPathEntered

要は、**業務上の境界だけはちゃんと地面に落とす** ということです。

### 4.3 「今書いている通常ログ」と「最後のクラッシュマーカー」は分ける

これはかなり大事です。

1 本の rolling log だけに全部入れようとすると、

- ローテーション中だった
- 非同期キューに残っていた
- 例外発生直後に logger 自体が死んだ
- ログ行の途中で切れた

ということが起きます。

なので、最低でも次の 2 本に分けるのがおすすめです。

- `app-<session>.jsonl`  
  通常時系列ログ
- `fatal-last.log` または `fatal-<session>.log`  
  最終クラッシュマーカー専用

**「最後の 1 行をどこに残すか」が明確** になっているだけで、現場でかなり助かります。

### 4.4 ログ保存先はローカル固定、ネットワーク先は使わない

クラッシュ時に UNC パス、NAS、HTTP、クラウド API に頼るのは危険です。

- ネットワーク瞬断
- DNS 遅延
- 資格情報失効
- UI スレッドでの待機
- サービスアカウント権限不足

が絡むからです。

クラッシュ時は **まずローカル固定パス** に落とします。  
送るのは **次回起動後か別プロセス** です。

### 4.5 ファイル名には session を入れる

日付だけでは足りません。  
同じ日に何回も再起動するからです。

おすすめは例えば次です。

```text
Logs\
  MyApp_20260318_101530_pid1234_session-4f1c.jsonl
  MyApp_fatal_20260318_101533_pid1234_session-4f1c.log
  MyApp_watchdog_20260318.jsonl
```

**「どの起動インスタンスの話か」** が明確なだけで、解析の速さがかなり変わります。

## 5. 最終クラッシュマーカーのベストプラクティス

ここは **フル機能 logger** を作る場所ではありません。  
**1 回だけ、短く、確実寄りに残す** 場所です。

### 5.1 目的は「原因の詳細」ではなく「入口の固定」

最終クラッシュマーカーに入れるべき情報は、絞ったほうが強いです。

- 発生 UTC
- PID / TID
- セッション ID
- バージョン / ビルド番号
- どのフックから来たか
  - `AppDomain.UnhandledException`
  - `Application.ThreadException`
  - `DispatcherUnhandledException`
  - `SetUnhandledExceptionFilter`
  - `_set_invalid_parameter_handler`
  - `set_terminate`
- 例外型または例外コード
- 可能なら簡単なメッセージ
- 直前の操作 ID
- 通常ログのファイル名
- dump 想定フォルダ

これだけで十分です。

### 5.2 クラッシュハンドラでやってはいけないこと

次はかなり高い確率で地雷です。

- DI コンテナから logger を解決する
- async / await を使う
- Task を投げる
- ロック待ちをする
- 複雑な JSON を組み立てる
- COM オブジェクトを触る
- UI ダイアログを出す
- 圧縮する
- HTTP / SMTP / Slack / Teams 送信
- dump を解析して要約する
- 例外を握りつぶして継続する

クラッシュハンドラは、**普通の処理フローの続きではない** です。  
「最小限のローカル書き込みだけして終わる」に寄せます。

### 5.3 クラッシュハンドラでやること

逆に、やることはかなり単純です。

1. 多重突入を防ぐ
2. 1 行だけ書く
3. flush する
4. 終了する

この順です。

できれば、

- 事前に作っておいた専用フォルダ
- 事前に存在確認済みのパス
- ACL を確認済みの保存先

を使います。

通常ログでは flush をやりすぎると重いですが、**fatal マーカーは件数が極小** なので、ここだけは強めに flush してよいです。  
.NET なら `FileStream.Flush(true)`、native なら `FlushFileBuffers` のように、**「この 1 行だけは今すぐ地面に落とす」** 扱いに寄せると設計しやすくなります。

### 5.4 継続させようとしない

プログラムミス起点の unexpected な例外なら、最終ハンドラは **回復装置ではなく記録装置** と考えたほうが安全です。

特に次は「継続しない」が基本です。

- `NullReferenceException` や `InvalidOperationException` でも、共有状態更新の途中だった
- UI スレッドで unexpected な例外
- 監視ループや親ループから漏れた unexpected 例外
- `AccessViolationException`
- `StackOverflowException`
- native 境界の異常
- CRT の invalid parameter / purecall / terminate

「落としたくない」気持ちは分かりますが、**半壊れで生き延びるほうが診断も運用もつらい** ことが多いです。

終了させるときは、`.NET` なら `Environment.FailFast`、native なら `RaiseFailFastException` や `__fastfail` のような **即時終了系 API** を検討し、`finally` や通常の後始末に期待しない設計のほうが安全です。

## 6. フレームワーク別の注意点

### 6.1 .NET 共通: `AppDomain.CurrentDomain.UnhandledException`

これは **最後の通知** として有用です。  
ただし、ここでの重い回復処理は避けます。

使い方の基本は次です。

- 最終クラッシュマーカーを書く
- 必要なら Windows Event Log に最小メッセージを残す
- 継続しない
- ここで待機や再試行をしない

`UnhandledException` は便利ですが、**ここでアプリを健康な状態へ戻せる前提にはしない** ほうが安全です。

### 6.2 WinForms: `Application.ThreadException`

これは、**UI スレッドの未処理例外を拾って見かけ上継続できてしまう** のが難しいところです。

業務入力の想定内エラーをダイアログ化する用途ならまだしも、  
**プログラムミス起点の unexpected 例外で継続する用途には向きません**。

本当に原因調査を優先するなら、

- `ThreadException` で最小記録だけする
- あるいは `UnhandledExceptionMode.ThrowException` に寄せる
- そのうえでプロセスを終了させ、ダンプとログを残す

のほうが安全です。

### 6.3 WPF: `Application.DispatcherUnhandledException`

WPF でも似ています。

- UI スレッド上の例外だけが主対象
- `Handled = true` にすると見かけ上継続できる
- でもプログラムミス相手にそれをやると、画面状態と内部状態がずれやすい

なので、WPF でも **継続のための延命装置としては使わず、記録の入口として使う** ほうが無難です。

### 6.4 `TaskScheduler.UnobservedTaskException` は主経路にしない

これは **「落ちる直前の最後の砦」** ではありません。

`Task` の例外取りこぼしを検知する補助には使えますが、  
**クラッシュ時の確実な記録経路としては弱い** です。

なので、

- 例外の観測漏れを早期に見つける
- 開発中に `Task` の設計漏れをあぶり出す

用途には使っても、**最終クラッシュハンドラの主役にはしない** ほうがよいです。

### 6.5 native Win32 / C++: `SetUnhandledExceptionFilter` を過信しない

native 側では、つい `SetUnhandledExceptionFilter` に期待したくなります。

ただし、これは **faulting thread の文脈で動く** ので、

- 無効スタック
- 深い再帰
- 既に壊れたヒープ
- 例外発生時のロック保持

の影響を受けます。

したがって、`SetUnhandledExceptionFilter` は  
**最後の通知を受ける best effort の入口** と考えるのがちょうどよいです。

### 6.6 native C++ は CRT の終了経路も拾う

native C++ では、未処理 SEH だけ見ていると漏れます。

見ておきたいのは例えば次です。

- `_set_invalid_parameter_handler`
- `_set_purecall_handler`
- `set_terminate`

この系統は、**C ランタイムや C++ ランタイム起点の「終了経路」** を拾うためのものです。

実務では、

- これらのハンドラでも最終クラッシュマーカーを書く
- ただし重い回復処理はしない
- 確実に終了させる
- 主証跡は WER / dump に任せる

が無難です。

## 7. WER LocalDumps を土台にする

ここが、実務ではかなり強いです。

### 7.1 まずのおすすめは WER LocalDumps

**「落ちたあとに最低限の証跡を確実寄りに残す」** という意味では、  
まずは WER LocalDumps が一番扱いやすいです。

理由は単純です。

- OS 側でダンプを残せる
- 追加ツールなしで入れやすい
- アプリ単位で設定できる
- クラッシュ時の主証跡を in-process 以外へ逃がせる

ログだけでは分からない

- どのスレッドが落ちたか
- どのスタックで落ちたか
- どのモジュール境界だったか
- managed / native / COM / SDK どこが怪しいか

を後から見られるのが強いです。

### 7.2 典型設定

例えば `MyApp.exe` について、`C:\CrashDumps\MyApp` にダンプを残すなら次のようにできます。

```bat
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpFolder /t REG_EXPAND_SZ /d "C:\CrashDumps\MyApp" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpCount /t REG_DWORD /d 10 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpType /t REG_DWORD /d 2 /f
```

最初は次の考え方でよいです。

| 値 | まずのおすすめ |
| --- | --- |
| `DumpFolder` | 専用フォルダ |
| `DumpCount` | 5〜10 |
| `DumpType` | 開発機は 2、現場は容量と機密要件を見て 1 or 2 |

### 7.3 dump 保存先の ACL を必ず確認する

ログでもダンプでも同じですが、**書けないフォルダに設定しても意味がありません**。

特に、

- Windows サービス
- 権限分離した子プロセス
- 現場機の制限アカウント
- UAC 絡み

では、**保存先 ACL が空振りの主因** になります。

保存先は、

- 事前作成
- 書き込みテスト
- 保持数制限
- 運用担当が見に行ける場所か

まで確認します。

### 7.4 WER レポートへ現在ログを添付したいとき

Microsoft への WER レポートや独自の WER 運用を使う場合は、`WerRegisterFile` で **現在のログファイルをエラーレポートに含めるための登録** を行う方法もあります。

ただし、ここは **ローカル保存の代替ではなく追加導線** と考えたほうが安全です。  
クラッシュ時に本当に欲しいのは、まず **手元の端末に確実寄りに残ること** だからです。

順番としては、

1. ローカル通常ログ
2. ローカル fatal マーカー
3. ローカル dump
4. 必要なら WER 送信経路でも関連ファイルを登録

のほうが実務向きです。

### 7.5 ダンプだけでなく版管理を残す

ダンプを取っても、後で

- その時の EXE / DLL がない
- PDB がない
- どのコミットのビルドか分からない

となると、かなり弱くなります。

最低でも次は残します。

- 配布したバイナリ
- 対応する PDB
- バージョン
- ビルド日時
- コミット識別子
- インストーラ版

ダンプ収集と PDB 保管は **セット** です。

## 8. `MiniDumpWriteDump` や独自クラッシュレポータを使うときの考え方

独自実装が必要になる場面もあります。

- UI から「診断情報を保存」ボタンを出したい
- ログや設定ファイルも束ねたい
- 子プロセス群をまとめて扱いたい
- 自動アップロード前に独自マスキングを入れたい

ただし、ここで一番大事なのは、**dump を取る処理も落ちる側に背負わせすぎない** ことです。

### 8.1 self-dump より別プロセス

`MiniDumpWriteDump` は強力ですが、  
**クラッシュしたそのプロセスの中から呼ぶより、別プロセスから呼ぶほうが安全** です。

典型構成は次です。

- worker 本体が異常を検知
- 可能ならイベントや名前付きパイプで helper に通知
- helper が worker の dump を取る
- helper が `tail` ログや設定ファイルを束ねる
- helper が終了後にアップロードキューへ置く

これなら、worker が壊れていても helper 側はまだ健全です。

### 8.2 どうしても in-process なら専用スレッドに寄せる

別プロセス化できない場合でも、  
**専用スレッドを dump 専用にしておく** とマシです。

ただし、それでも本質は best effort です。  
「独自 dump 実装を入れたから 100% 安心」にはなりません。

### 8.3 重いことは次回起動後に回す

独自レポータでやりたくなりがちなことがあります。

- zip 圧縮
- symbol 情報との突き合わせ
- サーバーアップロード
- 画面キャプチャ
- DB から追加情報取得

これらは **クラッシュ時ではなく、再起動後や helper 側** に回します。

## 9. 監視プロセスを入れると何が変わるか

長時間運転系では、監視プロセスがかなり効きます。

### 9.1 監視プロセスが残すもの

watchdog / launcher / 親サービスは、例えば次を残せます。

- 子プロセス開始時刻
- 起動引数
- PID
- 監視対象バージョン
- heartbeat の最終受信時刻
- 終了時刻
- exit code
- restart 回数
- dump の有無
- 再起動したかどうか

これがあるだけで、

- 本当にクラッシュしたのか
- OS シャットダウンだったのか
- ユーザーが閉じたのか
- hang から kill されたのか
- 何回再起動ループしたのか

がかなり見えます。

### 9.2 特に向いているケース

次なら、分離をかなり前向きに考えてよいです。

- vendor SDK を抱えた worker
- 画像処理 / 動画処理 / device I/O
- 監視やポーリングの親ループ
- スクリプトやプラグイン実行
- COM / ActiveX 既存資産のホスト
- 64bit / 32bit ブリッジや相互運用

**危ない処理を 1 個の worker に閉じ込める** と、ログ設計も復旧設計も楽になります。

## 10. よくある NG

### 10.1 `catch (Exception)` でログだけ出して続ける

一番ありがちで、一番危ないです。

- 途中変更が残る
- 共有状態が壊れる
- 後続障害が増える
- 真の原因地点がぼける

ログが 1 本増える代わりに、**事故が長引く** ことが多いです。

### 10.2 async logger のキューだけを信じる

非同期ログ自体は悪くありません。  
問題は、**fatal path でも同じキューへ積んで終わる** ことです。

落ちた瞬間にワーカーが止まれば、そのキューごと消えます。

**fatal path だけは直接書く** 逃げ道を持ったほうが安全です。

### 10.3 クラッシュハンドラで HTTP 送信する

実装したくなるのですが、かなり危険です。

- DNS
- TLS
- proxy
- 認証
- タイムアウト
- 再送待ち

全部が落ちた文脈に乗ります。

送るのは **再起動後** にします。

### 10.4 dump はあるが、通常ログと結びつかない

これは多いです。

- ダンプファイル名に session がない
- ログ側に PID / session がない
- watchdog 側に PID がない
- build 番号が一致しない

結果として、**3 つの証跡が別々の話に見える** ようになります。

### 10.5 WinForms / WPF の未処理例外イベントで延命する

見かけ上「落ちなくなる」ので、最初は喜ばれます。  
でも、実際には

- 画面だけ残る
- ワーカーは死んでいる
- ボタン活性だけ残る
- 保存できたかどうか分からない

というゾンビ状態を作りがちです。

### 10.6 native 側の終了経路を見ていない

`SetUnhandledExceptionFilter` だけで安心すると、

- invalid parameter
- purecall
- terminate
- fast fail

側を取りこぼします。

native C++ では、**SEH だけでなく CRT / C++ ランタイム側の終了経路も意識** したほうがよいです。

## 11. 最低限の導入チェックリスト

次を満たせば、かなり実戦的になります。

- [ ] 通常ログが 1 行 1 イベントで残る
- [ ] すべてのログに UTC、PID、TID、version、session がある
- [ ] `ProcessStart` と `ProcessExit` が残る
- [ ] 重要境界イベントは同期的に flush される
- [ ] 最終クラッシュマーカー専用ファイルがある
- [ ] fatal path では async logger を経由しない
- [ ] WER LocalDumps がアプリ単位で設定されている
- [ ] dump 保存先の ACL を検証済み
- [ ] PDB と配布バイナリを保管している
- [ ] 次回起動時に前回異常終了を検知できる
- [ ] 圧縮 / アップロード / 通知は再起動後または別プロセスで行う
- [ ] native C++ では invalid parameter / purecall / terminate も整理した
- [ ] 検証機で意図的に落として、**本当に残るか** を確認した

最後の 1 行が特に重要です。  
**設計しただけでは意味がなく、必ず「取り切る試験」をする** 必要があります。

## 12. どこまで試験するか

おすすめの確認項目は次です。

| 試験 | 何を確認するか |
| --- | --- |
| managed の未処理例外 | 通常ログ、fatal マーカー、dump が全部そろうか |
| UI スレッド例外 | WinForms / WPF のイベント経路が想定通りか |
| worker スレッド例外 | `AppDomain.UnhandledException` まで来るか、watchdog が検知できるか |
| native 例外 | WER dump が本当に取れるか |
| invalid parameter / terminate | CRT / C++ ランタイム経路でも最小記録が残るか |
| 強制 kill | in-process では無理でも watchdog 側が unexpected exit を記録できるか |
| 再起動 | 次回起動後の通知、回収、アップロードが動くか |

**「例外が飛んだらログが出るはず」ではなく、「この条件でこのファイルが残る」と確認する** のが大事です。

## 13. まとめ

Windows アプリがプログラムミスによる例外で落ちても、調査に必要な情報を残したいなら、考え方の軸はかなり単純です。

- **落ちる側のプロセスだけに期待しない**
- **通常ログ、最終クラッシュマーカー、OS / 別プロセス側の証跡に分ける**
- **クラッシュ時はローカルへ短く残すだけ**
- **重い処理は再起動後か別プロセスへ回す**
- **WER LocalDumps を土台にする**
- **継続より、記録して終了を基本にする**

要するに、  
**「最後の 1 行を頑張る」より、「最後の 1 行がなくても追える構成を作る」**  
ほうが強いです。

それでも最後の 1 行は欲しいので、  
**最終クラッシュマーカーは別ファイルに短く残す**。  
そして、本当の主証跡は **WER の dump と直前までの通常ログ** に持たせる。  
これが、Windows アプリの実務ではかなり安定したやり方です。

## 関連記事

- [Windows アプリのクラッシュダンプ収集入門 - まず WER / ProcDump / WinDbg をどう使い分けるか](https://comcomponent.com/blog/2026/03/16/008-windows-app-crash-dump-collection-introduction/)
- [想定していない例外が起きたとき、アプリを終了させるべきか継続すべきか - まず見る判断表](https://comcomponent.com/blog/2026/03/16/005-unexpected-exception-exit-or-continue-decision-table/)

## 参考資料

- Microsoft Learn: Collecting User-Mode Dumps  
  https://learn.microsoft.com/en-us/windows/win32/wer/collecting-user-mode-dumps
- Microsoft Learn: Using WER  
  https://learn.microsoft.com/en-us/windows/win32/wer/using-wer
- Microsoft Learn: MiniDumpWriteDump function  
  https://learn.microsoft.com/en-us/windows/win32/api/minidumpapiset/nf-minidumpapiset-minidumpwritedump
- Microsoft Learn: SetUnhandledExceptionFilter function  
  https://learn.microsoft.com/en-us/windows/win32/api/errhandlingapi/nf-errhandlingapi-setunhandledexceptionfilter
- Microsoft Learn: System.AppDomain.UnhandledException event  
  https://learn.microsoft.com/en-us/dotnet/fundamentals/runtime-libraries/system-appdomain-unhandledexception
- Microsoft Learn: Application.ThreadException Event  
  https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.application.threadexception
- Microsoft Learn: Application.DispatcherUnhandledException Event  
  https://learn.microsoft.com/en-us/dotnet/api/system.windows.application.dispatcherunhandledexception
- Microsoft Learn: TaskScheduler.UnobservedTaskException Event  
  https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.taskscheduler.unobservedtaskexception
- Microsoft Learn: Environment.FailFast  
  https://learn.microsoft.com/en-us/dotnet/api/system.environment.failfast
- Microsoft Learn: Registering for Application Recovery  
  https://learn.microsoft.com/en-us/windows/win32/recovery/registering-for-application-recovery
- Microsoft Learn: RegisterApplicationRecoveryCallback  
  https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-registerapplicationrecoverycallback
- Microsoft Learn: WerRegisterFile  
  https://learn.microsoft.com/en-us/windows/win32/api/werapi/nf-werapi-werregisterfile
- Microsoft Learn: _set_invalid_parameter_handler  
  https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/set-invalid-parameter-handler-set-thread-local-invalid-parameter-handler
- Microsoft Learn: _set_purecall_handler  
  https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/get-purecall-handler-set-purecall-handler
- Microsoft Learn: set_terminate  
  https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/set-terminate-crt
- Microsoft Learn: __fastfail  
  https://learn.microsoft.com/en-us/cpp/intrinsics/fastfail
