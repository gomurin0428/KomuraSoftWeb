---
title: "シリアル通信アプリの落とし穴 - 1 byte 単位、タイムアウト、フロー制御、再接続、USB 変換、UI フリーズを先に整理"
date: 2026-03-19 10:00
lang: ja
translation_key: serial-communication-app-pitfalls
tags:
  - シリアル通信
  - RS-232
  - C#
  - .NET
  - Windows開発
  - 装置連携
description: "装置連携や計測器制御で避けたいシリアル通信アプリの落とし穴を、フレーミング、タイムアウト、RTS/CTS、DTR/RTS、再接続、ログ設計まで実務目線で整理します。"
consultation_services:
  - id: windows-app-development
    reason: "シリアル通信を含む Windows アプリでは、受信処理、状態遷移、再接続、UI 分離まで含めて設計したほうが安定します。"
  - id: bug-investigation
    reason: "たまにだけ止まる、USB 抜き差し後だけ復帰しない、ログでは因果が追えないといった通信障害の切り分けと相性がよいテーマです。"
  - id: technical-consulting
    reason: "プロトコル境界、フロー制御、タイムアウト、single writer 設計を実装前に整理すると、後戻りの大きい不具合を減らしやすくなります。"
---

装置連携、計測器、PLC、バーコードリーダ、USB-シリアル変換。
シリアル通信は古い技術に見えて、Windows アプリの現場ではまだかなり普通に使われています。

少し危ないのは、シリアル通信が **1 本の COM ポート** と **1 本の `Read` / `Write`** だけで始められてしまうことです。疎通確認はすぐ通るのに、本番へ出すと次のような症状になりがちです。

- たまにコマンドと応答がずれる
- 1 日に 1 回だけ固まる
- USB の抜き差し後だけ復帰しない
- UI がときどき止まる
- ログを見ると "Timeout" しか残っていない

シリアル通信アプリで本当に難しいのは、送受信 API そのものではありません。難しいのは、**境界、タイムアウト、状態遷移、再接続、観測可能性** です。

## 1. まず結論

先に実務寄りの言い方でまとめると、押さえたいのは次です。

- シリアル通信は **順序付き byte stream** であって、メッセージ境界は勝手には付きません
- `Read(100)` したからといって 100 byte ぴったり返るとは限りません
- `.NET` の `DataReceived` は、**受信 byte ごとに発火するとは限らず**、しかも **UI スレッドでもありません**
- `ReadLine()` / `WriteLine()` は、相手が本当に行ベースのテキストプロトコルのときだけ素直です
- タイムアウトは 1 個では足りません。`open`、`inter-byte`、`response`、`reconnect` などの意味を分けたほうが安定します
- 送信はどこからでも `Write` できるようにするより、**single writer** に寄せたほうが崩れにくいです
- USB-シリアルでは、抜き差し、再列挙、COM 番号変化、再接続失敗を最初から前提にしたほうが平和です

要するに、シリアル通信アプリの難所は「ポートを開けるか」ではなく、**byte 列をどう意味あるメッセージへ変換し、その周辺の時間と状態をどう管理するか** です。

## 2. シリアル通信は「メッセージ」ではなく「順序付き byte stream」

アプリ側から見ると、シリアル通信は「コマンドを 1 つ送り、応答を 1 つ受ける」ように見えます。ただし下の層では、実際には **順序付きの byte 列** が流れているだけです。

つまり、こちらが 1 回 `Write` した内容が、相手側では次のように見える可能性があります。

- 1 回の `Read` で届く
- 2 回に分かれて届く
- ほかのデータと連結して届く

この前提を外すと、アプリ側で「今回の `Read` が今回の応答のはず」と思い込み始めます。この思い込みが、シリアル通信アプリの最初の地雷になりやすいです。

| よくある思い込み | 実際 |
| --- | --- |
| `Read(16)` なら 16 byte ちょうど返る | 到着状況やタイムアウト次第で途中までしか取れないことがあります |
| `DataReceived` = 1 メッセージ到着 | イベントは byte ごと保証されず、UI スレッドでもありません |
| `Write` が返った = 相手が処理完了した | 多くの場合、送信側がバッファへ積めたことに近いです |
| COM 一覧 = いま接続されている真実 | 列挙順は不定で、列挙結果が stale なこともあります |

このため、シリアル通信では **メッセージ境界をプロトコルとして自分で定義する** 必要があります。固定長フレーム、区切り文字ベース、長さ + payload + checksum など、形は何でもよいのですが、曖昧なまま実装に入ると後でほぼ確実に苦しくなります。

## 3. 最初に決めるべきこと

シリアル通信アプリを作る前に、少なくとも次は先に決めておいたほうが安全です。

### 3.1 フレーム境界

どの byte 列を 1 メッセージと見なすのかを決めます。固定長なのか、改行区切りなのか、長さ付きなのか、checksum / CRC があるのか。ここが曖昧だと、受信側は「まだ足りない」のか「壊れている」のか判断できません。

### 3.2 テキストか、バイナリか、その混在か

ASCII / UTF-8 の行プロトコルなのか、純バイナリなのか、両方混ざるのかを先に決めます。特に「コマンド部は文字列、payload はバイナリ、末尾だけ改行」のような混在は、どこまでを decode し、どこからを生 byte として扱うかを明示しないとすぐ境界が崩れます。

### 3.3 タイムアウトの意味

タイムアウトは 1 個ではなく、意味ごとに分けて考えたほうが安全です。

- open timeout: ポートを開けるまで
- inter-byte timeout: フレーム途中で byte が来ない時間
- response timeout: コマンド発行から応答完了まで
- reconnect backoff: 再接続の待機間隔

タイムアウトは「遅いときの保険」ではなく、**状態遷移を進めるためのルール** として持つと安定します。

### 3.4 フロー制御とライン状態

次は明示しておいたほうがよい設定です。

- `BaudRate`
- `DataBits`
- `Parity`
- `StopBits`
- `Handshake`
- `DTR` / `RTS`

ここを "8N1 でだいたい合う" で済ませると、相手装置によっては普通に止まります。

### 3.5 責務分離

次を誰が担当するのかを分けます。

- 誰が読むのか
- 誰が書くのか
- 誰がパースするのか
- 誰が業務状態へ反映するのか

シリアル通信は、UI と通信を混ぜるほど壊れやすくなります。

### 3.6 開始・停止・再接続の状態遷移

最低限、`Closed`、`Opening`、`Ready`、`WaitingResponse`、`Fault`、`Reconnecting` くらいの状態は設計しておいたほうが安全です。抜き差し直後、相手がまだ起動中かもしれませんし、前回の pending request を引きずってはいけないこともあります。

### 3.7 ログと調査性

後から一番困るのは、ほぼここです。最低限、open / close / reopen の時刻、使用したポート設定、送受信フレームの hex dump、checksum / CRC エラー、frame timeout / response timeout、再接続理由は残したいところです。

## 4. よくある落とし穴

### 4.1 `1 回の Read = 1 メッセージ` だと思う

一番多いのはこれです。たとえば相手がヘッダ、長さ、payload、CRC からなるフレームを返すとします。このとき `Read(buffer, 0, expectedLength)` を 1 回呼んで、その戻り値をそのまま 1 フレームだと思い込むと、途中受信で簡単に壊れます。

よくある壊れ方は次です。

- 長さだけ読めて payload がまだ来ていない
- 1 フレーム半だけ届いて、後半が次回の `Read` に回る
- 2 フレームがまとめて届いて、最初の 1 個だけ処理して残りを捨てる

対策は単純で、**受信はまず蓄積し、そこから parser がフレームを切り出す** 形に分けることです。

### 4.2 `DataReceived` をそのまま業務イベントにする

`.NET` の `SerialPort.DataReceived` は便利そうに見えますが、これを「1 メッセージ届いた通知」と思うと危険です。実務上は、`DataReceived` を「何か来たらしい」の通知と割り切り、ハンドラの中では重い処理をしないほうが安全です。UI 更新も必ず UI スレッドへ戻したほうがよいです。

### 4.3 どこからでも `Write` してよいと思う

UI のボタン、監視タイマー、再接続処理、keepalive がそれぞれ直接 `Write` する構成は崩れやすいです。シリアルは byte stream なので、設計次第ではコマンドの割り込みや応答待ち中の追い打ち送信が起きます。特に request-response 型や RS-485 系では、**single writer** に寄せたほうがかなり安定します。

### 4.4 `ReadLine()` / `WriteLine()` で全部通す

行ベースのテキストプロトコルなら `ReadLine()` / `WriteLine()` は便利です。ただし便利なのは、本当に **行プロトコルのときだけ** です。`NewLine` の不一致、payload 中の改行、文字コード差、バイナリ混在などがあると、すぐ境界が壊れます。

### 4.5 タイムアウトを設計せず、既定のままにする

同期 read を安易に置くと、普通に無限待ちになります。さらに厄介なのは、設定した timeout がすべての読み方に効くとは限らないことです。UI スレッドで同期 read する、1 個の timeout だけで全部を表現しようとする、retry だけ増やす、といった実装は詰まりやすいです。

### 4.6 RTS/CTS、XON/XOFF、DTR/RTS を軽く見る

ハンドシェイクや制御線は、実機相手ではかなり効きます。設定不一致があると、送信がたまに止まる、一定量を超えると取りこぼす、開いた直後だけ挙動が違う、といった症状になりがちです。実機によっては DTR/RTS の変化を、起動やモード切替の意味で見ていることもあります。

### 4.7 `Open()` のやり直しだけで再接続した気になる

特に USB-シリアルでは、一時的にポートが消える、旧ハンドルが無効になる、前回の pending request が意味を失う、といったことが普通に起こります。再接続は少なくとも、session 無効化、pending request の fail、reader / writer 停止、backoff 後の reopen、装置初期化の再実行までまとめて扱ったほうが安全です。

### 4.8 COM ポート列挙を真実だと思う

`GetPortNames()` は便利ですが、一覧に出たことと opening できることは同じではありません。前回の `COM7` を盲信する、列挙結果の先頭を自動選択する、一覧に出た時点で有効とみなす、といった実装は運用で困りやすいです。

### 4.9 送受信ログが薄い

`TimeoutException`、`IOException`、`Port closed` だけでは、ほぼ何も分かりません。送受信時刻、port profile、送受信 hex dump、parser error、どの request に対する response なのか、reconnect の契機が分かるようにしておくと、切り分けはかなり進みます。

## 5. ベストプラクティス

一番効くのは、責務を分けることです。

- `reader`: port から byte 列を読むだけ
- `writer`: outbound queue から順番に書くだけ
- `parser`: byte 列から frame を切り出すだけ
- `protocol`: request と response の対応や checksum を扱う
- `app state`: 業務状態を更新するだけ

受信処理は、`Read` の戻り単位をそのまま業務単位にせず、いったんバッファへ蓄積してから parser が frame を切り出す構成が安定します。送信は 1 本の worker に集約し、実際の `Write` を single writer に寄せたほうが順序ズレを減らせます。

タイムアウトも、ひとつの数字で済ませるより、open、inter-byte、response、reconnect の意味ごとに分けたほうが原因の切り分けがしやすくなります。port 設定はその場のコード値より profile として持ち、startup 時にログへ出しておくと現地調査がかなり楽になります。

再接続は、単なる reopen ではなく **session 再生成** と考えたほうが安定します。受信バッファ、parser 状態、pending request、初期化シーケンス、readiness 判定まで含めて作り直すと、「たまにだけ壊れる」再接続バグを減らしやすくなります。

最後に、生ログと要約ログを両方持つのがおすすめです。raw hex dump や open / close の履歴は調査に強く、request id や retry 回数の要約は運用に強いです。

## 6. まず見るチェックリスト

- メッセージ境界は明文化されているか
- 受信は byte 蓄積 → frame 切り出しになっているか
- `DataReceived` をメッセージ到着扱いしていないか
- UI スレッドで同期 I/O していないか
- 送信は single writer になっているか
- timeout が 1 個ではなく意味ごとに分かれているか
- `Handshake` / DTR / RTS が明示されているか
- reconnect で session を作り直しているか
- raw hex dump を残しているか
- 実機抜き差しや途中切断を試験しているか

この中でいくつも怪しい項目があるなら、本番投入前に一度整理したほうが安全です。

## 7. まとめ

押さえたい点をまとめると次です。

- シリアル通信はメッセージではなく byte stream
- `Read` 単位とメッセージ単位は一致しない
- 境界はプロトコルとして定義する必要がある
- `DataReceived` をそのまま業務イベントにすると崩れやすい
- 送受信は責務を分離し、送信は single writer に寄せる
- timeout は意味ごとに分割し、再接続は session 単位で設計する
- raw hex dump を含むログが、後の調査をかなり楽にする

つまり、シリアル通信アプリでは **ポートを開けること** より、**byte 列をどう解釈し、時間と状態をどう制御するか** のほうがずっと大事です。ここを最初に分けて設計するだけで、「たまにだけ壊れる」タイプの通信不具合はかなり減ります。

## 8. 参考資料

- Microsoft Learn, [`SerialPort.DataReceived` Event](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.serialport.datareceived)
- Microsoft Learn, [`SerialPort.Read` Method](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.serialport.read)
- Microsoft Learn, [`SerialPort.ReadTimeout` Property](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.serialport.readtimeout)
- Microsoft Learn, [`SerialPort.BaseStream` Property](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.serialport.basestream)
- Microsoft Learn, [`SerialPort.NewLine` Property](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.serialport.newline)
- Microsoft Learn, [`Handshake` Enum](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.handshake)
- Microsoft Learn, [`SerialPort.DtrEnable` Property](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.serialport.dtrenable)
- Microsoft Learn, [`SerialPort.RtsEnable` Property](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.serialport.rtsenable)
- Microsoft Learn, [`SerialPort.GetPortNames` Method](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.ports.serialport.getportnames)
- Microsoft Learn, [`SerialPort` Class](https://learn.microsoft.com/en-us/dotnet/api/system.io.ports.serialport)
- Microsoft Learn, [`COMMTIMEOUTS` structure](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-commtimeouts)
- Microsoft Learn, [`DCB` structure](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-dcb)
- Microsoft Learn, [`CreateFile` function](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilea)
- pySerial API, [Serial API Reference](https://pyserial.readthedocs.io/en/latest/pyserial_api.html)
