---
title: "外部機器の状態の確認と表示のベストプラクティス - 「接続中」だけで済ませない設計"
date: 2026-03-20T10:00:00+09:00
author: "小村 豪"
tags:
  - Windows
  - 外部機器
  - 装置連携
  - 状態管理
  - UI/UX
  - 監視
description: "外部機器連携アプリでは、状態を『接続中』の 1 つに潰すと誤案内が起きやすくなります。USB / シリアル / ネットワーク機器を前提に、検出、応答確認、動作可否、データ鮮度、表示文言、再接続までを実務向けに整理します。"
---

産業用カメラ、バーコードリーダ、PLC、計測器、プリンタ、シリアル機器、USB 機器。  
外部機器とつながる Windows アプリでは、**実際の不具合そのもの** より先に、**画面の状態表示が現実とズレること** で事故ることがかなり多いです。

たとえば、こんな状態です。

- OS からは見えているのに、別プロセスが掴んでいて使えない
- `open` はできたのに、原点復帰・ウォームアップ・認証が終わっていない
- 機器はぶら下がっているが、応答はもう止まっている
- 取得スレッドが死んでいるのに、最後の値だけ画面に残っている
- 想定外の個体や firmware なのに、単に「接続中」と表示してしまう

ここで本当に知りたいのは、**つながっているかどうか** だけではありません。  
**いま何を安全にやってよいか** です。

外部機器の状態確認で大事なのは、API の選び方よりも先に、

- 何を確認したら「接続済み」と言ってよいか
- 何を確認したら「使用可能」と言ってよいか
- いつから「値が古い」と言うべきか
- どの異常を operator 向けに強く見せるべきか

を決めることです。

この記事では、Windows アプリ、常駐監視アプリ、装置連携ツール、C# / .NET + ネイティブ SDK 混在のような実務を前提に、**外部機器の状態の確認と表示のベストプラクティス** を整理します。

## 目次

1. まず結論
2. なぜ「接続中」が危ないのか
3. まず分けるべき状態
4. 状態確認のベストプラクティス
   - 4.1 起動時列挙と到着 / 削除通知
   - 4.2 「存在」「開ける」「応答する」「使える」を分ける
   - 4.3 event と poll を混ぜる
   - 4.4 監視処理と UI を分離する
   - 4.5 個体識別を安定させる
5. 表示のベストプラクティス
   - 5.1 一枚で見る判断表
   - 5.2 文言は「状態 + 理由 + 次の行動」にする
   - 5.3 stale data を隠さない
   - 5.4 重要度に応じて見せる場所を変える
   - 5.5 複数台表示では要約と詳細を分ける
6. 再接続と運用のベストプラクティス
   - 6.1 再接続は backoff 付きにする
   - 6.2 flapping をならす
   - 6.3 最低限残すべきログ
   - 6.4 監視停止と機器停止を混同しない
7. 機器タイプ別の見落としやすい点
   - 7.1 USB / PnP 機器
   - 7.2 シリアル機器
   - 7.3 ネットワーク機器
   - 7.4 SDK 依存のカメラ / 計測機器
8. やってはいけないこと
9. まとめ
10. 参考資料

## 1. まず結論

先に、実務でかなり効くところだけ並べます。

- **外部機器の状態は boolean ではありません。** 少なくとも、`存在`、`セッション確立`、`応答性`、`機能準備`、`データ鮮度`、`構成一致` は分けて持ったほうが安全です。
- **起動時は列挙、以後は通知** が土台です。Windows では device interface の列挙と arrival / removal 通知を組み合わせます。通知だけでは既存機器は拾えません。[^1][^2][^3]
- **PnP 通知だけでは「使える」は分かりません。** 物理的に見えていることと、プロトコル的に応答することは別です。`heartbeat` や軽量 status query が要ります。
- **`open` 成功 = 使用可能** ではありません。busy、warming up、interlock open、media なし、設定不一致、別プロセス使用中、のような状態は別で出したほうがよいです。
- **表示している値には必ず時刻と age を持たせる** と事故が減ります。last known value を見せるなら、live value と見分けがつくようにします。
- **監視処理の健全性** は、機器の健全性と別です。取得ワーカーが死んだのに「未接続」と出すと、切り分けがかなり遅れます。
- **critical な異常を status bar の隅にだけ置かない** ほうが安全です。status bar は見落とされやすく、操作を止める必要がある異常には向いていません。[^7]
- **メッセージは vague にしない** ことが重要です。`エラー`、`異常`、`失敗しました` だけではなく、何が起きたか、何をすればよいかを出したほうがよいです。[^8]

かなり雑に言うと、こうです。

> **存在確認は OS 側、使用可否はアプリ側、鮮度判断は画面側で持つ。**

この 3 つを混ぜないだけで、状態表示はかなり安定します。

## 2. なぜ「接続中」が危ないのか

「接続中」という表示が危ないのは、1 つの文言で複数の意味を勝手に背負ってしまうからです。

実際には、少なくとも次の問いが混ざっています。

1. OS から対象機器の interface が見えているか
2. 自アプリがその機器を open / login / initialize できているか
3. 軽い問い合わせに期限内で返るか
4. いま要求した操作を安全に実行できるか
5. 画面に出ている値は新しいか
6. そもそも想定した個体・型番・firmware か

この 6 つのどれを満たしているかで、「使える」の意味は変わります。

たとえば、次の 4 つは全部違います。

- **未接続**  
  そもそも OS が対象 interface を見つけていない。
- **接続済み / 確認中**  
  物理的には見えているが、初期化や認証がまだ終わっていない。
- **接続済み / 使用不可**  
  見えていて応答もあるが、warming up、busy、interlock、media なしなどで操作できない。
- **値が古い**  
  以前は取得できていたが、今画面にある値は freshness budget を超えている。

ここを全部「接続中」で潰すと、operator は次のどれをすればよいのか判断できません。

- ケーブルを挿し直すべきか
- しばらく待てばよいのか
- 他プロセスを閉じるべきか
- 設定を見直すべきか
- いま見えている数値を信じてよいのか

つまり、表示の品質は UX だけの話ではなく、**安全に操作できるかどうか** の話でもあります。

## 3. まず分けるべき状態

最初におすすめしたいのは、**内部状態は多軸で持ち、UI では必要に応じて要約する** ことです。

最初から `Connected / Disconnected / Error` の 3 状態に潰すと、後で必ず足りなくなります。

### 3.1 内部で分けたい状態軸

| 軸 | 何を意味するか | 典型的な確認方法 | UI で見せたい例 |
|---|---|---|---|
| 存在 | OS から対象 interface が見えているか | 起動時列挙、arrival / removal 通知 | 未接続 / 接続済み |
| セッション | 自アプリが open / login / initialize 済みか | handle / session / SDK 初期化結果 | 確認中 / 初期化中 |
| 応答性 | 軽量問い合わせに期限内で返るか | heartbeat / status query / timeout | 応答あり / 応答遅延 / 応答なし |
| 機能準備 | 操作に必要な条件が揃っているか | device-specific status bits | 使用可能 / busy / warming up / media なし |
| データ鮮度 | 表示値が新しいか | timestamp / sequence / last success | 最新 / 値が古い |
| 構成一致 | 想定した個体・設定か | model / serial / firmware / profile | 対象機器 / 想定外の機器 |
| 監視健全性 | 自アプリの監視経路が動いているか | worker heartbeat / loop lag | 監視中 / 監視停止 |

ここで大事なのは、**「機器が悪い状態」** と **「アプリが観測できていない状態」** を分けることです。

たとえば、取得スレッドが落ちたときに「未接続」と出すと、operator はケーブルや機器を疑います。  
でも本当はアプリの内部障害です。

この取り違えを減らすためにも、`監視健全性` は独立で持ったほうが安全です。

### 3.2 UI は多軸をそのまま全部見せなくてよい

内部で 7 軸持つと、画面がうるさくなりそうに見えます。  
でも、UI は全部を平面的に出す必要はありません。

おすすめは、

- 一番上に **要約状態**
- その下に **理由**
- 必要なら **詳細パネル**

の 3 層です。

たとえば、

- 要約: `接続済み / 使用不可`
- 理由: `ウォームアップ中` `残り約 18 秒`
- 詳細: `model` `serial` `firmware` `last heartbeat` `last frame time`

のように分けると、情報量を増やしても読みにくくなりにくいです。

## 4. 状態確認のベストプラクティス

### 4.1 起動時列挙と到着 / 削除通知

Windows で外部機器を扱うときの土台は、**起動時に既存機器を列挙し、以後は arrival / removal 通知を受ける** ことです。[^1][^2][^3]

特に押さえておきたいのは次の点です。

- `CM_Register_Notification` は PnP event を callback で受けられますが、**既に存在している interface は通知してくれません**。既存 interface を知るには別途列挙が必要です。Microsoft Learn でも、まず `CM_Register_Notification` を呼び、その後 `CM_Get_Device_Interface_List` で existing interface を取得する流れが示されています。[^1]
- `RegisterDeviceNotification` を使うと、OS は device event を window または Windows service へ送れます。古いターゲット OS まで見るなら、`CM_Register_Notification` ではなくこちらを基準に考える場面があります。[^1][^2]
- runtime での機器検出や arrival / removal 通知は、**setup class ではなく device interface class** を基準に考えるほうが自然です。setup class は installation / configuration 向け、interface class は runtime communication 向けで、arrival / removal 通知にも interface class を使います。[^3]

ここから導ける実務ルールはシンプルです。

1. **起動時に列挙する**
2. **通知を購読する**
3. **通知を受けたら再列挙して、内部状態を reconcile する**

通知コールバックや window message handler の中で、いきなり重い I/O や再接続処理を最後までやる必要はありません。  
`CM_Register_Notification` の docs でも、PnP event handler はできるだけ速く返し、block する可能性がある処理は別 thread で非同期に行うことが推奨されています。[^1]

なので、通知は **edge trigger** と考えるのが実務では扱いやすいです。

- 通知を受けた
- dirty flag を立てる
- 背景 worker が再列挙 / 再照合する
- UI snapshot を更新する

このほうが race にも強くなります。

### 4.2 「存在」「開ける」「応答する」「使える」を分ける

ここはかなり重要です。

外部機器の状態確認は、だいたい次の順で積み上げると整理しやすいです。

#### 1. 存在確認

OS から対象 interface が見つかるか。  
これは **候補がいるかどうか** の確認です。

#### 2. 個体照合

見つかった候補が、本当に対象の個体か。  
複数台ある環境では、型番や friendly name だけでは危ないことがあります。serial、logical device ID、固有設定なども合わせて見ると安全です。

#### 3. セッション確立

その機器を、自アプリが実際に open / login / initialize できるか。  
ここで初めて、**自アプリから使える入口があるか** が分かります。

#### 4. 応答確認

軽い status query や heartbeat を期限内に返すか。  
この段階で、**つながってはいるが応答が止まっている** を拾います。

#### 5. 機能準備確認

いまやりたい操作に必要な条件が揃っているか。  
たとえば、

- 露光開始前のカメラ warm-up
- プリンタの用紙切れ
- スキャナの cover open
- PLC の remote/local mode
- 計測器の calibration 未完了

のようなものです。

#### 6. 鮮度確認

画面にある値が、新しいものとして扱ってよいか。  
最後に成功した時刻、sequence number、frame count、monotonic timestamp などで判断します。

この順に見ていくと、同じ「だめ」でも意味が変わります。

- 存在確認で落ちる → `未接続`
- セッション確立で落ちる → `使用中 / 初期化失敗 / 権限不足 / open 失敗`
- 応答確認で落ちる → `応答なし`
- 機能準備で落ちる → `接続済み / 使用不可`
- 鮮度確認で落ちる → `値が古い`

この分け方をしておくと、表示文言と retry 戦略も決めやすくなります。

### 4.3 event と poll を混ぜる

外部機器状態の確認でよくある失敗が、

- **PnP 通知だけに寄せる**
- **定期 polling だけに寄せる**

のどちらかに振り切ることです。

実務では、両方あったほうが扱いやすいです。

| 確認したいこと | 通知が強い | poll / heartbeat が強い | 理由 |
|---|---|---|---|
| 物理的な arrival / removal | ○ | △ | PnP / interface arrival-removal は OS 通知と相性がよい |
| 起動済み時点の既存機器検出 | × | ○ | 通知だけでは existing interface を拾えない[^1] |
| プロトコル上のハング | × | ○ | OS から見えていても応答が止まることがある |
| busy / ready / warming up | × | ○ | device-specific status はアプリが見にいく必要がある |
| 表示値の鮮度 | × | ○ | last success time や sequence はアプリ側の責務 |
| 切断直後の UI 追従 | ○ | ○ | 通知で素早く気づき、poll でも整合確認する |

要するに、

- **存在の変化** は OS 通知
- **生死と使用可否** はアプリ層の heartbeat / status query
- **値が生きているか** は画面側の freshness

で分担するのが分かりやすいです。

### 4.4 監視処理と UI を分離する

外部機器状態の確認は、**UI thread で直接やらない** ほうが安全です。

理由はシンプルで、機器 I/O は遅れます。

- ケーブル抜け
- 半二重通信の詰まり
- SDK 内部待ち
- TCP の timeout
- ドライバや firmware の遅延

このどれも、UI に直結させると画面が固まりやすくなります。

おすすめは、

- **device worker** が I/O と heartbeat を担当
- **state store / snapshot** が最新状態を保持
- **UI** は snapshot を購読して描画だけする

という分離です。

特にシリアル機器では、Windows は通信デバイス向けに `ClearCommError`、`COMMTIMEOUTS`、`WaitCommEvent` などを用意しています。`ClearCommError` は通信エラー情報と現在状態を返し、`COMMTIMEOUTS` は `ReadFile` / `WriteFile` 系の振る舞いを決め、`WaitCommEvent` は通信イベント監視に使えます。`WaitCommEvent` を使う場合は overlapped I/O 前提で扱うほうが安全です。[^4][^5][^6]

ここで大事なのは、**タイムアウトを全部の外部呼び出しに持たせる** ことです。

- open timeout
- status timeout
- command timeout
- shutdown timeout
- reconnect backoff

この境界がないと、「応答なし」ではなく「アプリが止まる」になります。

### 4.5 個体識別を安定させる

複数台接続環境では、**機器をどう識別するか** が状態表示の正しさに直結します。

危ないのは、次のような識別です。

- 一覧の n 番目
- `COM3`
- friendly name だけ
- IP アドレスだけ

これらは現場で変わりやすいです。

できれば、次のような安定キーを持ったほうがよいです。

- serial number
- device-specific logical ID
- interface path
- model + serial の組み合わせ
- ユーザーが付けた論理ラベルと個体 ID の対応

画面上は human friendly な名前を見せつつ、詳細には immutable に近い識別子も出しておくと、サポートと調査がかなり楽になります。

たとえば、

- 表示名: `前工程カメラ`
- 詳細: `Model: XC-2000 / Serial: A1B2C3 / Port: USB#...`

のような形です。

## 5. 表示のベストプラクティス

### 5.1 一枚で見る判断表

まずは、実務でいちばん使いやすい判断表を置きます。

| 画面に出す状態 | 裏で満たす条件 | 画面の例 | ユーザーに許可する操作 |
|---|---|---|---|
| 未接続 | OS から対象 interface が見えていない | `未接続` `対象機器が見つかりません` | 再スキャン、設定確認 |
| 接続済み / 確認中 | interface は見えているが、open / 初期化 / 認証中 | `接続済み / 確認中` | 待機、キャンセル |
| 使用可能 | 応答あり、ready 条件 OK、freshness OK | `使用可能` `最終更新 12:41:08` | 本操作を許可 |
| 接続済み / 使用不可 | 応答ありだが busy / warming up / media なし | `接続済み / 使用不可` `ウォームアップ中` | 本操作は抑止 |
| 応答遅延 | 直近で timeout や retry 増加があるが復旧余地あり | `応答遅延` `自動再試行中` | 注意付きで一部操作 |
| 値が古い | 取得値 age が budget 超過 | `値が古い` `最終更新 23 秒前` | live 前提の操作は禁止 |
| 設定不一致 | model / serial / firmware / profile が期待と違う | `想定外の機器` | 操作禁止、設定誘導 |
| 監視停止 | 自アプリの worker / poll loop が止まっている | `監視停止` `再起動が必要です` | 再開 / 再起動誘導 |
| 重大エラー | 安全に継続してよい保証がない | `機器状態を確認できません` | 操作停止、明示的対応 |

この表でいちばん大事なのは、**`未接続` と `監視停止` を分ける** ことと、**`使用可能` と `接続済み` を分ける** ことです。

### 5.2 文言は「状態 + 理由 + 次の行動」にする

状態表示の文言は、次の 3 点が揃うとかなり分かりやすくなります。

1. **いまの状態**
2. **その理由**
3. **次に何をすればよいか**

悪い例は、こうです。

- `エラー`
- `接続に失敗しました`
- `異常`
- `通信エラー`

これだと、現場で判断ができません。

もう少し良い形は、たとえば次です。

| よくない表示 | 改善した表示 |
|---|---|
| `接続エラー` | `機器に応答がありません。5 秒後に再接続します。` |
| `異常` | `接続済みですが、別プロセスが使用中です。対象アプリを閉じてから再試行してください。` |
| `未接続` | `指定した個体を検出できません。期待 serial: A1B2C3` |
| `OK` | `使用可能。最終更新 12:41:08（0.4 秒前）` |
| `失敗しました` | `firmware が想定と異なります。必要: 2.4.1 / 実際: 2.3.7` |

Windows の UX ガイドでも、status bar の情報は useful and relevant であるべきで、critical な情報には向かないこと、また error message は vague にせず具体的に書くことが推奨されています。[^7][^8]

なので文言は、

- 何が起きたか
- 何ができないか
- 何をすればよいか

まで出すと、サポートコストも下がります。

### 5.3 stale data を隠さない

外部機器表示で見落とされやすいのが、**last known value を live value の顔で見せてしまう** ことです。

これはかなり危険です。

たとえば、温度、重量、位置、カメラ画像、検査結果。  
これらが 10 秒前の値なのか 200 ms 前の値なのかで、意味はまったく変わります。

そこで、次をおすすめします。

- 値そのものと一緒に **`最終更新時刻`** を出す
- もしくは **`n 秒前`** を出す
- freshness budget を超えたら、明示的に **`値が古い`** と出す
- stale 状態では live 前提の操作を抑止する
- last known value を残すなら、見た目を変える

たとえば、

- 色を落とす
- `LIVE` バッジを外す
- `最終取得値` とラベル付けする
- グラフに `更新停止` オーバーレイを出す

のような形です。

ここはかなり大事で、**時刻は値の一部** くらいに考えたほうが安全です。

### 5.4 重要度に応じて見せる場所を変える

Windows の UX ガイドでは、status bar は background task や contextual information には向く一方、**users must see it な情報には向かない** とされています。見落としやすいからです。[^7]

なので、表示場所は次のように分けると整理しやすいです。

| 情報の種類 | 向いている場所 |
|---|---|
| 非重要な現在状態 | status bar、一覧の 1 列、詳細ペイン |
| 作業を止める必要がある異常 | 主画面内の目立つ領域、インラインメッセージ、モーダルではない警告領域 |
| 操作直結の入力不備 | 対象コントロールの近く |
| 長時間処理の進行状況 | 進捗バー、タスク単位の UI |
| 一時的な通知 | toast ではなく履歴に残る通知領域も検討 |

特に避けたいのは、

- critical な異常を status bar の端に出すだけ
- toast だけ出して消える
- 重要な停止理由をログにしか残さない

です。

operator が即時に判断すべき情報は、**見つけにいかなくても見える場所** に置いたほうが安全です。

### 5.5 複数台表示では要約と詳細を分ける

複数台の機器を扱う画面では、全件詳細を常に出すと見づらくなります。  
おすすめは、

- 上部に **全体サマリ**
- 下部に **機器ごとの行**
- 選択時に **詳細ペイン**

の 3 段です。

たとえば、4 台カメラなら、上部は

- `4 台中 3 台使用可能 / 1 台応答遅延`

だけでもよく、個別行に

- `前工程カメラA: 使用可能`
- `前工程カメラB: 値が古い（最終更新 12 秒前）`
- `後工程カメラA: ウォームアップ中`

を並べると、かなり分かりやすくなります。

ここでも、**全体サマリは最悪状態を要約しつつ、個別理由は隠さない** ことが大事です。

## 6. 再接続と運用のベストプラクティス

### 6.1 再接続は backoff 付きにする

応答が止まったときの再接続は、**最短ループで叩き続けない** ほうが安全です。

理由は単純で、

- device / driver / SDK に負荷をかける
- ログが洪水になる
- 一時的な不安定を悪化させる
- UI が激しく揺れる

からです。

おすすめは、

- 初回はすぐ retry
- だめなら段階的に間隔を伸ばす
- 上限を設ける
- 手動 `再接続` も用意する

という形です。

また、自動 retry 中であっても UI は

- `再接続中`
- `5 秒後に再試行`

のように出して、**いま何をしているか** を隠さないほうがよいです。

### 6.2 flapping をならす

USB ケーブル接触不良、ハブ不安定、ネットワーク瞬断、SDK 再接続の途中。  
こういう場面では、状態が短時間に `接続` / `未接続` を行き来することがあります。

ここで、生のイベントをそのまま UI に出すとかなり見づらくなります。

なので、

- 内部ログは生イベントのまま残す
- UI は短い確認期間を置いてから確定表示する
- ただし critical 異常はすぐ見せる

という使い分けが実務では扱いやすいです。

要するに、**観測は生、表示は少し整える** です。

### 6.3 最低限残すべきログ

状態表示の改善は、ログ設計とほぼセットです。

最低限、次くらいは残しておくと後で効きます。

| 項目 | 例 |
|---|---|
| timestamp | `2026-03-20T10:23:41.512+09:00` |
| stable device key | `camera:A1B2C3` |
| 表示名 | `前工程カメラ` |
| 旧状態 -> 新状態 | `Ready -> Stale` |
| 理由 | `heartbeat timeout` `firmware mismatch` |
| エラーコード | `HRESULT` `Win32` `SDK code` |
| last success | `2026-03-20T10:23:36.011+09:00` |
| age / RTT | `5.5s` `320ms` |
| retry count | `3` |
| app / firmware version | `App 1.8.2 / FW 2.4.1` |
| worker instance | `poller-2` |

特に大事なのは、**状態遷移ログ** です。

- ずっと `未接続`
- `使用可能` だったが `応答遅延` に落ちた
- `値が古い` を経由して `監視停止` になった

この順番が見えるだけで、原因切り分けがかなり変わります。

### 6.4 監視停止と機器停止を混同しない

これは本当に重要です。

- poll loop が例外で死んだ
- SDK callback が止まった
- acquisition worker が `deadlock` した
- state store 更新だけ止まった

こういうとき、機器は生きていても、アプリはもう観測できていません。

この状態を `未接続` や `応答なし` だけで出すと、機器側の問題に見えてしまいます。

なので、**アプリ内監視経路の健全性** を持ったほうがよいです。

たとえば、

- worker heartbeat の最終時刻
- 監視ループの周期逸脱
- 例外終了回数
- queue の滞留時間

を見て、しきい値を超えたら `監視停止` や `監視異常` を出します。

24/7 系の無人運転アプリなら、ここは外部 supervisor / service / watchdog まで含めて設計したほうが安全です。

## 7. 機器タイプ別の見落としやすい点

### 7.1 USB / PnP 機器

USB / PnP 機器では、arrival / removal 通知と interface 列挙が基本です。[^1][^2][^3]

ただし、気を付けたいのは次です。

- **通知だけでは existing device を拾えない**
- **setup class ではなく interface class で見たほうが runtime には自然**
- **composite device は複数 interface を出す** ことがある
- **remove 通知と I/O error の見え方が前後する** ことがある

要するに、USB 的に「いる」ことと、アプリ的に「使える」ことは別です。

### 7.2 シリアル機器

シリアル機器では、`COMx` が見えているだけでは安心できません。

- ポート自体はあるが、対象機器がぶら下がっていない
- 別プロセスが open している
- 物理接続はあるが、プロトコル上は死んでいる
- read / write が timeout で固まる

Windows では `ClearCommError` が通信エラー情報と現在状態を返し、`COMMTIMEOUTS` が読み書きの timeout 挙動を決め、`WaitCommEvent` が通信イベント監視に使えます。特に `WaitCommEvent` は overlapped I/O と組み合わせて、他の処理を止めないようにしたほうが安全です。[^4][^5][^6]

表示上は、少なくとも次を分けると実務で役に立ちます。

- `ポートが見つからない`
- `ポートを開けない`
- `ポートは開けたが応答がない`
- `応答はあるが、機器状態が操作を許していない`

### 7.3 ネットワーク機器

ネットワーク機器で見落とされやすいのは、`ping` が通ることと、アプリが使えることを同一視することです。

実際には、

- 名前解決できるか
- TCP 接続できるか
- アプリ層 handshake / login できるか
- device status が ready か
- 値が fresh か

で段階が違います。

なので、ネットワーク機器では

- `到達可`
- `接続可`
- `認証済み`
- `使用可能`

を分けて考えると整理しやすいです。

### 7.4 SDK 依存のカメラ / 計測機器

産業用カメラや計測器では、SDK が callback や event を隠蔽してくれることがあります。  
このとき危ないのは、**SDK callback が来ている = live** と決め打ちすることです。

実際には、

- callback thread 自体が止まる
- frame は来るが timestamp が進んでいない
- image stream は来るが control channel が死んでいる
- device は reconnect したが、設定再適用が終わっていない

といったことがあります。

なので、SDK 依存機器では

- 最終 frame 時刻
- frame sequence の進み
- control command の往復時間
- 設定適用済みフラグ

のような **SDK の外から見た健全性** も持っておくと安全です。

## 8. やってはいけないこと

最後に、かなり事故りやすいものをまとめます。

- **状態を `接続中 / 未接続 / エラー` の 3 つに潰す**
- **通知だけで existing device も拾えると思う**
- **setup class GUID で arrival / removal を追う**
- **`open` 成功をそのまま `使用可能` とみなす**
- **last known value を fresh な顔で見せる**
- **timestamp を表示しない**
- **UI thread で open / read / status query を直に呼ぶ**
- **retry を最短ループで回す**
- **critical な異常を status bar や一瞬の toast にだけ出す**
- **`未接続` と `監視停止` を混同する**
- **friendly name や `COM3` だけで個体識別する**
- **文言を `異常` `エラー` `失敗しました` だけで済ませる**

このあたりを避けるだけで、状態表示の事故率はかなり下がります。

## 9. まとめ

外部機器連携アプリで本当に大事なのは、**何を確認したら、どこまで言ってよいか** を決めることです。

とくに、次の整理が効きます。

> **存在している**  
> **自アプリが開ける**  
> **応答している**  
> **いまその操作ができる**  
> **画面の値が新しい**

この 5 つを分ける。

そのうえで、かなり雑に言うと次です。

- **起動時は列挙、以後は通知**
- **使用可否は heartbeat と device-specific status で決める**
- **表示値には timestamp と age を持たせる**
- **critical な異常は見落とされにくい場所へ出す**
- **監視系の異常を機器異常に見せない**

「接続中」と出せることより、  
**その表示が現実とどれだけズレにくいか** のほうが、実務ではずっと大事です。

外部機器の状態表示は、見た目の問題ではありません。  
**運用の迷いを減らし、安全に次の行動を選べるようにする設計** です。

## 10. 参考資料

- Microsoft Learn, [CM_Register_Notification function (cfgmgr32.h)](https://learn.microsoft.com/en-us/windows/win32/api/cfgmgr32/nf-cfgmgr32-cm_register_notification)
- Microsoft Learn, [Registering for Notification of Device Interface Arrival and Device Removal](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/registering-for-notification-of-device-interface-arrival-and-device-removal)
- Microsoft Learn, [Registering for Device Notification](https://learn.microsoft.com/ja-jp/windows/win32/devio/registering-for-device-notification)
- Microsoft Learn, [Comparison of setup classes and interface classes](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/comparison-of-setup-classes-and-interface-classes)
- Microsoft Learn, [Device Information Sets](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/device-information-sets)
- Microsoft Learn, [SetupDiEnumDeviceInterfaces function (setupapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/setupapi/nf-setupapi-setupdienumdeviceinterfaces)
- Microsoft Learn, [Communications functions](https://learn.microsoft.com/ja-jp/windows/win32/devio/communications-functions)
- Microsoft Learn, [ClearCommError function (winbase.h)](https://learn.microsoft.com/ja-jp/windows/win32/api/winbase/nf-winbase-clearcommerror)
- Microsoft Learn, [COMMTIMEOUTS structure (winbase.h)](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-commtimeouts)
- Microsoft Learn, [WaitCommEvent function (winbase.h)](https://learn.microsoft.com/ja-jp/windows/win32/api/winbase/nf-winbase-waitcommevent)
- Microsoft Learn, [Monitoring Communications Events](https://learn.microsoft.com/ja-jp/windows/win32/devio/monitoring-communications-events)
- Microsoft Learn, [Status Bars (Design basics)](https://learn.microsoft.com/en-us/windows/win32/uxguide/ctrl-status-bars)
- Microsoft Learn, [UX checklist for desktop applications](https://learn.microsoft.com/en-us/windows/win32/uxguide/top-violations)

[^1]: Microsoft Learn, [CM_Register_Notification function (cfgmgr32.h)](https://learn.microsoft.com/en-us/windows/win32/api/cfgmgr32/nf-cfgmgr32-cm_register_notification) / [Registering for Notification of Device Interface Arrival and Device Removal](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/registering-for-notification-of-device-interface-arrival-and-device-removal)
[^2]: Microsoft Learn, [Registering for Device Notification](https://learn.microsoft.com/ja-jp/windows/win32/devio/registering-for-device-notification)
[^3]: Microsoft Learn, [Comparison of setup classes and interface classes](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/comparison-of-setup-classes-and-interface-classes) / [Device Information Sets](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/device-information-sets) / [SetupDiEnumDeviceInterfaces function (setupapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/setupapi/nf-setupapi-setupdienumdeviceinterfaces)
[^4]: Microsoft Learn, [Communications functions](https://learn.microsoft.com/ja-jp/windows/win32/devio/communications-functions) / [ClearCommError function (winbase.h)](https://learn.microsoft.com/ja-jp/windows/win32/api/winbase/nf-winbase-clearcommerror)
[^5]: Microsoft Learn, [COMMTIMEOUTS structure (winbase.h)](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-commtimeouts)
[^6]: Microsoft Learn, [WaitCommEvent function (winbase.h)](https://learn.microsoft.com/ja-jp/windows/win32/api/winbase/nf-winbase-waitcommevent) / [Monitoring Communications Events](https://learn.microsoft.com/ja-jp/windows/win32/devio/monitoring-communications-events)
[^7]: Microsoft Learn, [Status Bars (Design basics)](https://learn.microsoft.com/en-us/windows/win32/uxguide/ctrl-status-bars)
[^8]: Microsoft Learn, [UX checklist for desktop applications](https://learn.microsoft.com/en-us/windows/win32/uxguide/top-violations)
