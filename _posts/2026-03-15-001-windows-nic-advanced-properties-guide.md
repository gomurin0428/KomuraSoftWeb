---
title: "Windows における NIC の詳細設定をまとめて整理 - ジャンボパケット、RSS、LSO、RSC、フロー制御、EEE、Wake on LAN まで"
date: 2026-03-15 10:00
lang: ja
translation_key: windows-nic-advanced-properties-guide
tags:
  - Windows
  - ネットワーク
  - NIC
  - Ethernet
  - 性能チューニング
  - Windows開発
description: "Windows の NIC 詳細設定を実務目線で整理します。Jumbo Packet、Speed & Duplex、RSS、RSC、LSO、Flow Control、EEE、Wake on LAN など、設定を変えると何が変わるかをまとめます。"
consultation_services:
  - id: technical-consulting
    reason: "NIC 設定単体ではなく、通信経路、アプリの送受信パターン、長期稼働条件まで含めて整理したいテーマなので、技術相談・設計レビューと相性がよいです。"
  - id: bug-investigation
    reason: "リンク断、100Mbps へのダウンシフト、復帰不良、スループット低下の切り分けは、不具合調査・原因解析として進めやすい題材です。"
---

Windows の NIC の **[Advanced] タブ** は、見慣れない単語がかなり並びます。  
`Jumbo Packet`、`Large Send Offload`、`Interrupt Moderation`、`Receive Side Scaling`、`Flow Control`、`Energy Efficient Ethernet`。名前だけを見ると全部有効にしたくなりますが、実際には **何を優先したいか** で正解が変わります。

- 大容量転送のスループットを上げたいのか
- 小さい packet のレイテンシを詰めたいのか
- CPU 使用率を下げたいのか
- スリープ復帰や Wake on LAN を安定させたいのか
- ドライバやスイッチとの相性問題を切り分けたいのか

ここが曖昧なまま「とりあえず全部 On」「とりあえず Jumbo 9014」「遅いから 1Gbps Full に固定」をやると、かなり普通に事故ります。

この記事では、主に **Windows 10 / 11 / Windows Server の有線 Ethernet アダプタ** を対象に、NIC の詳細設定を実務で触るときの考え方を整理します。  
設定の意味、値を上げる / 下げる / 有効化 / 無効化すると何が起きやすいか、どんな場面で触るべきかを、まとめて見渡せるように書いていきます。

なお、NIC の表示名や選べる値は **ベンダーとドライバでかなり変わります**。  
`Jumbo Packet` が `Jumbo Frames` だったり、`Receive Buffers` が `Receive Descriptors` だったり、`Priority & VLAN` が `Packet Priority & VLAN` だったりします。この記事では、意味が近いものはまとめて扱います。

## 1. まず結論

最初に、実務で外しにくい結論だけ先に置きます。

- **Speed & Duplex は基本 Auto** です。100Mbps に落ちる問題で、いきなり `1.0 Gbps Full Duplex` 固定に走るのは最後です。
- **Checksum Offload / RSS / LSO / RSC は、原則は有効または既定値** です。雑に全部切ると CPU を無駄に食いやすくなります。
- **Jumbo Packet は end-to-end で揃うときだけ** 使います。NIC だけ 9014 にしても、途中経路が 1500 のままだと落とし穴です。
- **Interrupt Moderation は throughput と latency の綱引き** です。高めにすると CPU は楽になりますが、レイテンシは増えます。
- **Flow Control は drops を減らす方向に効くことがありますが、輻輳を広げることもあります。**
- **EEE / Green Ethernet / Selective Suspend は省電力のための設定** で、速くする設定ではありません。
- **VMQ / SR-IOV は Hyper-V ホスト向け** で、普通のデスクトップ PC を速くする魔法ではありません。
- **Wake on Pattern Match は意図しない wake の原因になりやすい** ので、Wake on LAN が欲しいだけなら Magic Packet に寄せるほうが安全です。
- **TCP Chimney Offload など古い項目は今は触らない** ほうがよいです。

要するに、NIC の詳細設定は「強そうなものを全部有効にする場所」ではありません。  
**スループット、レイテンシ、CPU、消費電力、互換性のどれを取りに行くのか** を決めて、1 個ずつ触る場所です。

## 2. どこで設定を見るか

### 2.1 GUI で見る

#### ネットワーク接続から入る

1. `ncpa.cpl` を実行
2. 対象アダプタを右クリック
3. **プロパティ** → **構成**
4. **詳細設定 (Advanced)** タブ

#### デバイスマネージャから入る

1. デバイスマネージャ
2. **ネットワーク アダプター**
3. 対象 NIC を右クリック → **プロパティ**
4. **詳細設定** タブ

ここに並ぶ項目が、この記事の主役です。  
ただし、**Power Management タブの設定** も実務ではかなり効くので、後半で扱います。

### 2.2 PowerShell で見る

PowerShell だと、今の値を一覧で見たり、変更前のバックアップを取ったりしやすいです。

```powershell
Get-NetAdapter

Get-NetAdapterAdvancedProperty -Name "Ethernet" |
  Sort-Object DisplayName |
  Format-Table DisplayName, DisplayValue, RegistryKeyword, RegistryValue -Auto
```

NIC によっては `RegistryKeyword` が標準化された名前になっていて、`*RSS`、`*VMQ`、`*SRIOV`、`*EEE` のように見えることがあります。  
ただし、**DisplayName と DisplayValue はドライバ依存** です。変更スクリプトを書くときは、実機でまず一覧を見たほうが安全です。

## 3. 触る前の大原則

NIC 設定を触る前に、ここを外すとだいたい沼ります。

### 3.1 まず「何を良くしたいか」を決める

同じ「ネットワークが遅い」でも、中身はまったく別です。

- 大きなファイルコピーが遅い  
  → throughput、RSS、RSC、LSO、Jumbo、バッファ
- 小さい request/response がもたつく  
  → Interrupt Moderation、RSC、EEE、キュー深さ
- CPU が高い  
  → オフロード、RSS、RSC、割り込み
- スリープ復帰後におかしい  
  → Selective Suspend、Power Management、WoL
- たまに切れる / 100Mbps になる  
  → ケーブル、相手機器、Speed & Duplex、EEE、ドライバ

目的が違うのに同じ設定を触ると、改善どころか悪化します。

### 3.2 まず物理層と相手機器を疑う

NIC 設定では直らない問題も普通にあります。

- ケーブル不良
- スイッチ / ルータ / dock の相性
- 古い firmware
- USB NIC の電力不足
- ポート側のエラー
- パケットロスや再送

特に **100Mbps に落ちる**、**リンクがフラップする**、**大容量転送だけ壊れる** は、設定より先に物理と相手を見るほうが早いです。

### 3.3 1 回に 1 項目だけ変える

Jumbo、LSO、RSC、RSS、EEE を一気に変えると、何が効いたのか分からなくなります。  
変更前の設定を書き出して、**1 項目ずつ** 変えて、変化を測るのが基本です。

### 3.4 測るものを決める

最低でも、次は見たいところです。

- リンク速度（1G / 2.5G / 10G など）
- スループット
- レイテンシ
- CPU 使用率
- NIC の統計（drop / error / buffer shortage）
- スリープ復帰の安定性

設定変更は、体感だけでなく数字で見るほうが強いです。

## 4. 主要設定の一覧表

まずは、設定ごとの役割を一枚で見られる表を置きます。

| 設定 | 何をする設定か | 上げる / 有効にすると起きやすいこと | 下げる / 無効にすると起きやすいこと | 基本方針 |
| --- | --- | --- | --- | --- |
| Speed & Duplex | リンク速度と duplex の交渉 / 固定 | 古い相手と合わせれば繋がることはあるが、不一致だと duplex mismatch や速度低下 | Auto に戻すと modern な機器では安定しやすい | **基本は Auto** |
| Jumbo Packet / Jumbo Frames | MTU より大きいフレームを使う | 大きな転送で CPU と header overhead が減りやすい | 互換性は高いが packet 数は増える | **専用経路で end-to-end に揃うときだけ** |
| Checksum Offload | IP / TCP / UDP の checksum を NIC で処理 | CPU が下がりやすい | OS 側計算が増えて CPU が上がりやすい | **原則有効** |
| LSO / TSO | 大きな TCP 送信データを NIC が分割 | send-heavy な throughput と CPU に効きやすい | CPU 負荷は増えるが相性切り分けには使いやすい | **通常は有効** |
| RSC / LRO | 受信 TCP セグメントを NIC 側で結合 | 受信 throughput と CPU に効きやすい | 粒度が細かくなり、低レイテンシでは有利なことがある | **受信重視なら有効** |
| RSS | 受信処理を複数 CPU に分散 | multi-core で throughput / scalability が上がりやすい | 単一 CPU 集中で詰まりやすい | **multi-core では有効が基本** |
| Interrupt Moderation | 割り込み頻度を抑制 | CPU が楽になるが latency は増えやすい | latency は下がるが CPU / DPC 負荷が上がりやすい | **既定 / Adaptive を起点** |
| Receive / Transmit Buffers | リング / バッファの深さ | burst 耐性や sustained throughput に効きやすい | メモリ消費は減るが drop に弱くなる | **不足時だけ増やす** |
| Flow Control | 802.3x pause frame の送受信 | drop を減らせることがある | tail latency には有利なことがある | **ネットワーク全体設計と合わせる** |
| Priority & VLAN | 802.1p / 802.1Q タグ付け | VLAN / QoS を使える | 単純な L2 として動く | **必要なときだけ** |
| VMQ / SR-IOV | Hyper-V / 仮想化向けの NIC 支援 | VM throughput / CPU に効く | 通常ホストとしては単純になる | **Hyper-V ホスト向け** |
| EEE / Green Ethernet | 省電力のための Low-Power Idle | 消費電力は下がるが相性問題が出ることがある | 電力は増えるが安定しやすいことがある | **速度設定ではない** |
| Selective Suspend | NIC を idle 時に低電力化 | 電力は下がる | 復帰安定性は上がることがある | **トラブル時は切り分け候補** |
| Wake on Magic Packet / Pattern Match | スリープ中の wake 条件 | 遠隔起動できる | 意図しない wake を防ぎやすい | **必要なときだけ有効** |

## 5. リンクとフレームサイズまわりの設定

### 5.1 Speed & Duplex

これは **リンク速度と全二重 / 半二重の交渉** に関する設定です。表示名は `Speed & Duplex`、`Link Speed`、`Link Speed & Duplex` などがあります。

#### 何をしている設定か

Ethernet では、NIC と相手機器が、どの速度・どの duplex で通信するかを決めます。

- Auto Negotiation
- 100 Mbps Full Duplex
- 1.0 Gbps Full Duplex
- 2.5 Gbps Full Duplex
- 10 Gbps Full Duplex

のような選択肢が出ることが多いです。

#### 変更するとどう変わるか

**Auto にする**

- 現代の機器同士では、基本これが一番安定します
- 1000BASE-T 以上では Auto が前提になる場面が多いです
- EEE や master/slave の交渉とも整合しやすいです

**手動で固定する**

- 古いスイッチや、相手側が強制固定されている機器との相性で改善することがあります
- ただし、**片側だけ固定 / 片側だけ Auto** のような状態は事故の元です
- duplex mismatch を起こすと、速度低下、再送、異常な遅延の原因になります

#### 実務上の基本方針

**普通は Auto のままでよい** です。  
「1Gbps 出ないから 1Gbps Full に固定」は、見た目は強そうですが芯を外すことが多いです。

### 5.2 Jumbo Packet / Jumbo Frames

これは **標準より大きな Ethernet フレームを使う設定** です。表示名は `Jumbo Packet`、`Jumbo Frames`、`Jumbo Packet Size` などがあります。

#### 何をしている設定か

通常の Ethernet は **MTU 1500** を前提に動くことが多いです。Jumbo Frame を有効にすると、**9000 byte 前後** の大きなフレームを使えるようになります。

ただし、ここは名前の罠が多いです。

- ドライバは `9014 Bytes` のように **フレームサイズ** を表示することがある
- OS やツールは `MTU 9000` のように **L3 視点** で見ることがある
- スイッチは **CRC や VLAN タグ込み** で数えることがある

数字だけ横並びで見比べると、かなり普通にハマります。

#### 変更するとどう変わるか

**大きくする / 有効にする**

- 大きなデータを送るとき packet 数が減る
- header 処理回数が減る
- CPU 使用率が下がりやすい
- 一方で、**1 packet あたりの占有時間は長くなる**
- 経路上のどこかが未対応だと drop や fragmentation の原因になる

**標準に戻す / 無効化する**

- 互換性は最も高い
- packet 数は増える
- 大容量転送では CPU / header overhead が増えやすい

#### 実務上の基本方針

Jumbo は **end-to-end** で揃って初めて意味があります。

- 自分の NIC
- 相手の NIC
- 途中のスイッチ
- VLAN や仮想スイッチを挟むならその overhead

このどれかが 1500 のままだと、効果が出ないどころか不具合の元になります。

### 5.3 Gigabit Master / Slave Mode

これは 1000BASE-T で、**どちらが master、どちらが slave としてクロックを主導するか** に関わる設定です。普通の PC ではまず触りません。

#### 基本方針

- **Auto** が基本
- 特定の古い相手機器との link quality 問題でだけ評価する
- ベンダー指示がない限り、性能 tuning のつまみとしては扱わない

### 5.4 Wait for Link / Link 状態系の設定

`Wait for Link` のような設定は、**ドライバが auto negotiation の成功を待ってから link 状態を報告するか** に関わります。  
`Log Link State Event` は link up/down をイベントログに残す診断用です。

#### 基本方針

- 通常の PC は既定値のままでよい
- 性能そのものより、起動時の見え方や failover の診断で意味がある
- まず触る項目ではない

## 6. CPU 負荷、スループット、レイテンシに効く設定

ここが、いちばん「効きそう」に見える帯です。実際に効くことも多いですが、効く方向がきれいに分かれます。

### 6.1 Checksum Offload

IP / TCP / UDP の checksum 計算を NIC に寄せる設定です。

#### 基本方針

- **原則有効**
- CPU を下げたいなら残す
- capture 上の checksum error は offload の見え方であることが多い
- 相性切り分けで一時的に切るのはあり

### 6.2 Large Send Offload (LSO) / TSO / Offload TCP Segmentation

大きな TCP 送信データを NIC 側で細かい frame に分割する設定です。

#### 何に効くか

- send-heavy な throughput
- CPU 使用率の削減
- 大きめの連続送信

#### 基本方針

- 通常は **有効**
- 特定アプリやドライバ相性が怪しいときは一時的に無効化して差を見る

### 6.3 Receive Segment Coalescing (RSC) / Large Receive Offload

受信側で複数の TCP segment をまとめる設定です。

#### 何に効くか

- 受信側の throughput
- CPU 使用率の削減

#### 注意点

- 低レイテンシや packet 単位の観測では不利になることがある
- capture やタイミング観測の解釈が少し変わる

#### 基本方針

- **受信 throughput を取りたいなら有効**
- **小さい request/response の latency を見たいなら評価対象**

### 6.4 UDP 系の新しめのオフロード (USO / URO)

最近の NIC や OS では、UDP の送受信でも新しめの offload が見えることがあります。

#### 基本方針

- 出ていても、まずは既定値から外れない
- ドライバが十分新しく、対象 workload がはっきりしているときだけ測る
- トラブルシュートでは無理に触らない

### 6.5 Receive Side Scaling (RSS)

受信処理を複数 CPU に分散させる設定です。multi-core 環境ではかなり重要です。

#### 基本方針

- **multi-core では有効が基本**
- 単一 CPU に張り付いている症状ではまず確認する
- Hyper-V や high-throughput の手前でも主役になりやすい

### 6.6 RSS Queues / RSS Processors / RSS Profile

RSS の並列度を決める項目です。

#### 基本方針

- 既定値から始める
- CPU 使用率や queue 偏りが見えてから増やす
- むやみに最大まで増やすと割り込みや DPC 負荷が増えることがある

### 6.7 Interrupt Moderation / Interrupt Moderation Rate

割り込み頻度を抑制して、CPU 負荷と latency を交換する設定です。

#### 傾向

- 高め / Adaptive  
  → CPU が楽になりやすいが latency は増えやすい
- 低め / Off  
  → latency は下がりやすいが CPU / DPC 負荷は上がりやすい

#### 基本方針

- **既定 / Adaptive を起点**
- 小さい packet の jitter が気になるなら Low / Off を評価
- 大容量転送なら既定値のほうが素直なことが多い

### 6.8 Receive Buffers / Receive Descriptors と Transmit Buffers / Transmit Descriptors

リング / バッファの深さを変える設定です。

#### 効く方向

- burst 耐性
- sustained throughput
- drop 回避

#### 副作用

- メモリ消費が増える
- queue が深くなって待ち行列遅延が増えることがある

#### 基本方針

- drop や buffer shortage が見えているときだけ増やす
- なんとなく最大にするのは避ける

### 6.9 Flow Control

802.3x pause frame の送受信に関する設定です。

#### 基本方針

- drop を減らしたいなら候補になる
- ただし pause が別の輻輳を広げることもある
- 低レイテンシ系では慎重に見る
- **ネットワーク全体設計とセットで考える**

## 7. VLAN、QoS、仮想化まわりの設定

### 7.1 Priority & VLAN / Packet Priority & VLAN / NDIS QoS

802.1Q VLAN や 802.1p Priority を扱う帯です。

#### 基本方針

- VLAN / QoS を本当に使うときだけ意識する
- 単純な access port 環境なら既定値のままでよい
- タグが勝手に付く構成は切り分けを難しくするので注意する

### 7.2 VMQ / VMMQ / SR-IOV

これは **Hyper-V ホストや仮想化基盤** で意味が出る設定です。

#### 基本方針

- 普通の desktop tuning としては扱わない
- Hyper-V ホストなら vSwitch 構成、queue 割り当て、ゲスト側設定と一体で評価する
- 片側だけ見ても正解は出にくい

### 7.3 RDMA / DCB / PFC は別世界

このあたりは SMB Direct や lossless Ethernet を含む、かなり別世界です。

#### 基本方針

- 通常の 1GbE / 2.5GbE デスクトップ調整とは切り分けて考える
- ベンダー資料とスイッチ側設計をセットで確認する

## 8. 省電力、スリープ、Wake on LAN まわりの設定

### 8.1 Energy Efficient Ethernet (EEE) / Green Ethernet

省電力のために、リンク idle 時の消費電力を落とす設定です。

#### 見方

- 速くする設定ではない
- 消費電力には効く
- 相手機器やケーブル条件によっては、リンク不安定や 100Mbps downshift の切り分け候補になる

#### 基本方針

- 一般用途では既定値でもよい
- リンク不安定、100Mbps 化、低レイテンシ重視では **まず切り分け候補**

### 8.2 Selective Suspend / Device Sleep / Standby 時リンク制御

要するに、**idle 時やスリープ時に NIC をどこまで眠らせるか** の設定です。

#### 基本方針

- ノート PC では既定値から開始
- 復帰トラブルがあるなら最初に疑う
- 装置制御 PC や 24/7 運用では、むしろ切るほうが分かりやすいことがある

### 8.3 Wake on Magic Packet / Wake on Pattern Match

これはスリープ中の PC を、ネットワーク経由で起こすための設定です。

#### 基本方針

- **Wake on LAN が必要なら Magic Packet を有効**
- **不要なら無効**
- **Pattern Match は必要性が明確なときだけ**

NIC だけ On にしても起きないことは普通にあります。BIOS / UEFI 側や Power Management タブ側も揃えて見ます。

### 8.4 ARP Offload / NS Offload

スリープ中でも NIC が最低限の応答を肩代わりする設定です。

#### 基本方針

- 通常は **有効 / 既定値** でよい
- スリープ周りの相性切り分けで一時的に触ることが多い

### 8.5 Power Management タブの設定

Advanced タブとは別に、NIC のプロパティには **Power Management** タブがあります。ここも地味に重要です。

よく見るのは次の 3 つです。

- **Allow the computer to turn off this device to save power**
- **Allow this device to wake the computer**
- **Only allow a magic packet to wake the computer**

#### 基本方針

- 復帰不良なら、まず `Allow the computer to turn off this device...` を疑う
- 誤起床を避けたいなら `Only allow a magic packet...` を有効にする
- Wake on LAN 自体が不要なら wake 系は全部無効でよい

## 9. そのほかの、よく見るが触る機会は少ない設定

### 9.1 Network Address / Locally Administered Address

**MAC アドレスを手動で上書きする** 設定です。

#### 基本方針

- 普段は触らない
- 性能設定ではない
- ラボ環境や特殊要件でだけ使う

### 9.2 Adaptive Inter-Frame Spacing

かなり古参の設定です。現代の switched full-duplex Ethernet では主役ではありません。

#### 基本方針

- **現代の普通の LAN では既定値のまま**
- 古い装置や特殊環境でベンダー指示があるときだけ触る

### 9.3 Header Data Split

主にサーバ向けで、packet header と payload を分けて扱うことで CPU 処理を助ける類いの設定です。

#### 基本方針

- サーバ向け / 特定 workload 向け
- 一般クライアントでは既定値のまま

### 9.4 Low Latency Interrupts

ベンダーによっては `Low Latency Interrupts` のような項目があります。

#### 基本方針

- 測って勝つときだけ使う
- 雰囲気で On にする帯ではない

### 9.5 TCP Chimney Offload / IPsec Task Offload などの古い項目

古めの NIC やドライバでは、こうした項目を見ることがあります。

#### 基本方針

- **今は触らない、使わない** が正解
- 互換性や古い資料に引っ張られない

## 10. 目的別のざっくり指針

### 10.1 普通のデスクトップ / ノート PC

- Speed & Duplex: **Auto**
- MTU / Jumbo: **1500 / 無効**
- Checksum Offload: **有効**
- LSO: **有効**
- RSC: **有効**
- RSS: **有効**
- Interrupt Moderation: **既定値 / Adaptive**
- Buffers: **既定値**
- Flow Control: **既定値**
- EEE / Green Ethernet: **既定値**
- Selective Suspend: **既定値**
- Wake on LAN: **必要なときだけ**

つまり、**まずは既定値から外れない** のが基本です。

### 10.2 NAS / バックアップ / 大容量コピー

- Speed & Duplex: **Auto**
- Jumbo: **専用経路で揃えられるなら評価**
- Checksum Offload: **有効**
- LSO: **有効**
- RSC: **有効**
- RSS: **有効**
- RSS queues: **必要なら少し増やす**
- Receive / Transmit Buffers: **drop があるなら少し増やす**
- Interrupt Moderation: **既定値 / やや高め**
- EEE: **安定性重視なら無効評価**

大きな転送では、**packet 数削減、CPU 削減、queue 不足回避** が効きやすいです。

### 10.3 産業用カメラ / 装置制御 / 低レイテンシ重視

- Speed & Duplex: **Auto を基本。必要なら相手に合わせて固定**
- Jumbo: **カメラ / NIC / スイッチが揃うなら評価**
- Checksum Offload: **まず有効**
- LSO: **送信相性が怪しければ一時的に無効評価**
- RSC: **低レイテンシや観測優先なら無効候補**
- Interrupt Moderation: **Low / Off を評価**
- Buffers: **増やしすぎない**
- Flow Control: **pause の副作用を要評価**
- EEE / Green Ethernet: **無効候補**
- Selective Suspend / 電力管理: **無効候補**

throughput 最適化の設定が、必ずしも low latency に有利ではありません。

### 10.4 Hyper-V ホスト

- VMQ / VMMQ / SR-IOV: **構成に応じて評価**
- RSS: **ホスト側トラフィックには重要**
- RSC: **vSwitch 構成によって制約あり**
- QoS / VLAN: **vSwitch 設計と合わせる**
- Flow Control / PFC: **ストレージ / RDMA 設計と一体で考える**

これは desktop tuning ではなく、**仮想化基盤設計** です。

### 10.5 トラブルシュート用の一時設定

不具合切り分けでは、いったん単純な世界に戻すのが強いです。

- Speed & Duplex: **Auto**
- MTU: **1500**
- Jumbo: **無効**
- EEE: **無効**
- LSO: **一時的に無効**
- RSC: **一時的に無効**
- Interrupt Moderation: **既定値または低め**
- Wake / power save: **不要なら無効**
- 変更前設定: **必ず保存**

切り分けでは、**性能最適化より挙動の単純化** が勝ちます。

## 11. 症状別の最初の当たりどころ

### 11.1 1Gbps / 2.5Gbps のはずが 100Mbps になる

まず見る順番は、だいたい次です。

1. ケーブル
2. dock / USB NIC / 変換アダプタ
3. スイッチ側ポート
4. ドライバ更新
5. EEE / Green Ethernet
6. Speed & Duplex を Auto に戻す
7. それでもだめなら、相手と合わせた固定を試す

**いきなり手動固定は最後** です。

### 11.2 大容量転送は遅いが、ping は普通

見たいのは次です。

- Checksum Offload
- LSO
- RSC
- RSS
- Receive / Transmit Buffers
- Jumbo Frame（専用経路なら）
- NIC 統計の drop / error

これは **throughput 系の問題** なので、Jumbo や queue、offload が効きやすいです。

### 11.3 小さい request/response の遅延が大きい、jitter が気になる

見たいのは次です。

- Interrupt Moderation
- RSC
- EEE
- Flow Control
- Buffers を盛りすぎていないか

この帯では、**まとめて処理する系の最適化** が、逆に体感遅延を増やすことがあります。

### 11.4 スリープ復帰後に NIC が消える / 数秒つながらない

見たいのは次です。

- Selective Suspend
- Device Sleep / Standby 関連設定
- Power Management タブの `Allow the computer to turn off this device...`
- dock / USB NIC の firmware
- Wake 設定の組み合わせ

復帰トラブルは、NIC そのものより **電源管理** のことが多いです。

### 11.5 packet capture で checksum error が大量に見える

慌てて「回線が壊れた」と言う前に、次を確認します。

- Checksum Offload が有効か
- LSO が有効か
- capture が送信前か、wire 上か
- 別ホストやミラーポートで見たときも同じか

ローカル capture の checksum error は、**offload の見え方** であることが本当に多いです。

### 11.6 Hyper-V の VM だけ遅い / CPU が偏る

見るべきは desktop 的な RSS だけではありません。

- VMQ / VMMQ
- SR-IOV
- vSwitch binding
- VLAN / QoS
- ホスト側 RSS と VM 側 queue の分担

仮想化では、**誰が packet をさばいているか** を図にすると整理しやすいです。

## 12. PowerShell で確認・変更するときの実用メモ

### 12.1 まず現状を保存する

変更前のバックアップは大事です。

```powershell
Get-NetAdapterAdvancedProperty -Name "Ethernet" |
  Select-Object Name, DisplayName, DisplayValue, RegistryKeyword, RegistryValue |
  Export-Csv .\nic-advanced-backup.csv -NoTypeInformation -Encoding UTF8
```

### 12.2 一覧を見る

```powershell
Get-NetAdapterAdvancedProperty -Name "Ethernet" |
  Sort-Object DisplayName |
  Format-Table DisplayName, DisplayValue, RegistryKeyword -Auto
```

### 12.3 RSS / RSC / 統計を見る

```powershell
Get-NetAdapterRss -Name "Ethernet"
Get-NetAdapterRsc -Name "Ethernet"
Get-NetAdapterStatistics -Name "Ethernet"
```

### 12.4 変更例

実際の表示名は NIC ごとに違うので、まず一覧を見てから変更します。

```powershell
# 例: Jumbo Packet を変更（値は NIC ごとに違う）
Set-NetAdapterAdvancedProperty -Name "Ethernet" `
  -DisplayName "Jumbo Packet" `
  -DisplayValue "9014 Bytes"
```

```powershell
# 例: RSS の受信キュー数を設定
Set-NetAdapterRss -Name "Ethernet" -NumberOfReceiveQueues 4
```

### 12.5 Jumbo の疎通確認

```powershell
# 標準 MTU 1500 相当
ping <相手IP> -f -l 1472

# MTU 9000 相当
ping <相手IP> -f -l 8972
```

`1472` と `8972` は、IP / ICMP header を差し引いた payload です。ドライバ UI の `9014 Bytes` と、この ping の数字は一致しません。

### 12.6 実務メモ

- 一部の設定は **アダプタの無効 / 有効** や再起動が必要です
- DisplayName がローカライズされている場合があります
- 同じベンダーでも driver version で項目名が変わることがあります
- PowerShell で自動化するなら、**実機の値を先に列挙してから** 書くほうが安全です

## 13. まとめ

Windows の NIC 詳細設定は、項目名だけ見ると全部「強そう」です。  
でも実際には、**throughput、latency、CPU、power、compatibility のどれを取るかで正解が変わる** 世界です。

この記事の要点をまとめると、こうです。

- **Speed & Duplex は基本 Auto**
- **Jumbo は end-to-end で揃うときだけ**
- **Checksum / RSS / LSO / RSC は原則既定値が強い**
- **Interrupt Moderation は throughput と latency のトレードオフ**
- **Buffers は必要な分だけ**
- **EEE / Selective Suspend / Wake 系は power / resume の話**
- **VMQ / SR-IOV は Hyper-V の話**
- **古い offload 項目は触らない**

そして、いちばん大事なのは次の 3 つです。

1. **何を良くしたいのかを決める**
2. **1 回に 1 項目だけ変える**
3. **変更前後を数字で比べる**

NIC 設定は、魔法の速くなるスイッチではありません。  
ただし、目的が合っていればかなり効きます。逆に、目的がズレるとかなり素直に裏目を引きます。

## 14. 参考資料

以下は、この記事を書くときに土台として参照した公式資料 / ベンダー資料です。  
Windows や NIC ドライバは用語揺れが多いので、最終的には **自分の NIC のドライバ名とバージョン** に合わせて確認するのが安全です。

- Microsoft Learn: [NIC advanced properties](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/nic-advanced-properties)
- Microsoft Learn: [Network Adapter Performance Tuning in Windows Server](https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics)
- Microsoft Learn: [Hardware Only (HO) features and technologies](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/hardware-only-features)
- Microsoft Learn: [Overview of Single Root I/O Virtualization (SR-IOV)](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/overview-of-single-root-i-o-virtualization--sr-iov-)
- Microsoft Learn: [Standardized INF Keywords for NDIS QoS](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/standardized-inf-keywords-for-ndis-qos)
- Microsoft Learn: [Standardized INF Keywords for Power Management](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/standardized-inf-keywords-for-power-management)
- Microsoft Learn: [Setting RSS parameters](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/setting-rss-parameters)
- Microsoft Learn: [Overview of receive segment coalescing](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/overview-of-receive-segment-coalescing)
- Microsoft Learn: [How to optimize network adapter power management settings](https://learn.microsoft.com/en-us/troubleshoot/windows-client/networking/power-management-on-network-adapter)
- Microsoft Learn: [Deprecated networking features in Windows Server](https://learn.microsoft.com/en-us/windows-server/get-started/removed-deprecated-features-windows-server#deprecated-features)
- Intel Support: [Advanced Settings for Intel Ethernet Adapters](https://www.intel.com/content/www/us/en/support/articles/000005593/ethernet-products.html)
- Intel Support: 速度固定、Jumbo、Interrupt Moderation、EEE、WoL などは NIC 型番ごとのサポート記事から確認するのが安全です
