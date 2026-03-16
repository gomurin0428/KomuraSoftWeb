---
title: Windows における NIC の詳細設定をまとめて整理 - ジャンボパケット、RSS、LSO、RSC、フロー制御、EEE、Wake on LAN まで
slug: windows-nic-advanced-properties-guide
description: Windows の NIC の詳細設定を実務目線で整理します。ジャンボパケット、Speed & Duplex、RSS、RSC、LSO、チェックサムオフロード、Interrupt Moderation、Flow Control、VLAN/QoS、VMQ / SR-IOV、EEE、Selective Suspend、Wake on LAN など、設定を変えると何が変わるのかを網羅的に解説します。
date: 2026-03-15T10:00:00+09:00
author: 小村 豪
tags:
  - Windows
  - ネットワーク
  - NIC
  - Ethernet
  - 性能チューニング
  - Windows開発
---

Windows の NIC の **[Advanced] タブ** は、見慣れない単語がぎっしり並ぶわりに、説明がかなり薄いです。  
`Jumbo Packet`、`Large Send Offload`、`Interrupt Moderation`、`Receive Side Scaling`、`Flow Control`、`Energy Efficient Ethernet`。名前だけ見ると全部速そうですが、実際には **何を優先するか** で正解が変わります。

- 大容量転送のスループットを上げたいのか
- 小さいパケットのレイテンシを詰めたいのか
- CPU 使用率を下げたいのか
- スリープ復帰や Wake on LAN を安定させたいのか
- ドライバやスイッチとの相性問題を切り分けたいのか

ここを曖昧にしたまま「とりあえず全部 On」「とりあえず Jumbo 9014」「遅いから 1Gbps Full に固定」は、かなり普通に事故ります。

この記事では、主に **Windows 10 / 11 / Windows Server の有線 Ethernet アダプタ** を対象に、NIC の詳細設定を実務で使う目線で整理します。  
それぞれの設定について、**何のための設定か、値を上げる / 下げる / 有効化 / 無効化すると何が起きやすいか、どんな場面で触るべきか** までまとめます。

なお、NIC の表示名や選べる値は **ベンダーとドライバでかなり変わります**。  
`Jumbo Packet` が `Jumbo Frames` だったり、`Receive Buffers` が `Receive Descriptors` だったり、`Priority & VLAN` が `Packet Priority & VLAN` だったりします。この記事では、意味が近いものはまとめて扱います。

## 目次

1. まず結論
2. どこで設定を見るか
3. 触る前の大原則
4. 主要設定の一覧表
5. リンクとフレームサイズまわりの設定
6. CPU 負荷、スループット、レイテンシに効く設定
7. VLAN、QoS、仮想化まわりの設定
8. 省電力、スリープ、Wake on LAN まわりの設定
9. そのほかの、よく見るが触る機会は少ない設定
10. 目的別のざっくり指針
11. 症状別の最初の当たりどころ
12. PowerShell で確認・変更するときの実用メモ
13. まとめ
14. 参考資料

---

## 1. まず結論

最初に、実務で外しにくい結論だけ先に置きます。

- **Speed & Duplex は基本 Auto** です。100Mbps に落ちる問題で、いきなり `1.0 Gbps Full Duplex` 固定に走るのは最後です。まずケーブル、相手機器、ドライバ、EEE を見ます。
- **Checksum Offload / RSS / LSO / RSC は、原則は有効または既定値** です。雑に全部切ると、CPU を無駄に食いがちです。
- **Jumbo Packet は end-to-end で揃うときだけ** 使います。NIC だけ 9014 にしても、途中のスイッチや相手が 1500 のままだと、ただの落とし穴です。
- **Interrupt Moderation は throughput と latency の綱引き** です。高めにすると CPU は楽になりますが、レイテンシは増えます。低め / Off にすると、その逆です。
- **Receive/Transmit Buffers は「大きければ勝ち」ではありません。** バースト耐性や sustained throughput は上がりやすいですが、メモリを食い、場合によっては待ち行列の遅延も増えます。
- **Flow Control は drops を減らす方向に効くことがありますが、輻輳を広げることもあります。** 特に低レイテンシ系では慎重に見ます。
- **EEE / Green Ethernet / Selective Suspend / Standby 時のリンク制御は、省電力のための設定** です。速くする設定ではありません。リンク不安定、復帰不良、100Mbps への downshift では、むしろ切り分け候補です。
- **VMQ / SR-IOV は Hyper-V ホスト向け** です。普通のデスクトップ PC の「速くなる設定」ではありません。
- **Wake on Pattern Match は意図しない wake の原因になりやすい** ので、Wake on LAN が欲しいだけなら Magic Packet のみに寄せるほうが安全です。
- **TCP Chimney Offload や IPsec Task Offload のような古い項目は、今は触らないほうがよい** です。

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

同じ「ネットワークが遅い」でも、実際には別問題です。

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

NIC 設定で直らないものは、普通にあります。

- ケーブル不良
- スイッチ / ルータ / dock の相性
- 古いファームウェア
- USB NIC の電力不足
- ポート側のエラー
- パケットロスや再送

特に **100Mbps に落ちる**、**リンクがフラップする**、**大容量転送だけ壊れる** は、設定より先に物理と相手を見るべきです。

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
細かい話は後ろでやります。

| 設定 | 何をする設定か | 上げる / 有効にすると起きやすいこと | 下げる / 無効にすると起きやすいこと | 基本方針 |
|---|---|---|---|---|
| Speed & Duplex | リンク速度と duplex の交渉 / 固定 | 古い相手と合わせれば繋がることはあるが、不一致だと duplex mismatch や速度低下 | Auto に戻すと modern な機器では安定しやすい | **基本は Auto** |
| Jumbo Packet / Jumbo Frames | MTU より大きいフレームを使う | 大きな転送で CPU とヘッダ overhead が減りやすい。途中機器不一致だと drop しやすい | 互換性は高いが、パケット数は増える | **専用経路で end-to-end に揃うときだけ** |
| Checksum Offload | IP / TCP / UDP の checksum を NIC で処理 | CPU が下がりやすい。ほかのオフロードの前提にもなる | OS 側計算が増えて CPU が上がりやすい | **原則有効** |
| LSO / TSO | 大きな TCP 送信データを NIC が分割 | send-heavy な throughput と CPU に効きやすい | CPU 負荷は増えるが、相性切り分けには使いやすい | **通常は有効、相性問題では一時的に無効** |
| RSC / LRO | 受信 TCP セグメントを NIC 側で結合 | 受信 throughput と CPU に効きやすい | パケット粒度が細かくなり、低レイテンシでは有利なことがある | **受信重視なら有効、低遅延なら要評価** |
| RSS | 受信処理を複数 CPU に分散 | multi-core で throughput / scalability が上がりやすい | 単一 CPU 集中でボトルネックになりやすい | **multi-core では有効が基本** |
| RSS Queues / Max RSS Processors | RSS の並列度 | 多コアを使えるが、割り込みと CPU overhead も増える | CPU を節約できるが、並列性を失う | **既定値から必要時だけ増やす** |
| Interrupt Moderation | 割り込み頻度を抑制 | CPU が楽になるが、レイテンシは増えやすい | レイテンシは下がるが、CPU / DPC 負荷が上がりやすい | **既定 / Adaptive を起点** |
| Receive Buffers | 受信リング / バッファの深さ | burst 耐性、受信 throughput、drop 回避に効きやすい | メモリ消費は減るが、受信 drop が増えやすい | **受信 drop があるとき増やす** |
| Transmit Buffers | 送信リング / バッファの深さ | burst 耐性、送信 throughput に効きやすい | メモリ消費は減るが、送信側の詰まりに弱くなる | **送信性能不足時だけ増やす** |
| Flow Control | 802.3x pause frame の送受信 | drop を減らせることがあるが、輻輳を広げることもある | tail latency には有利なことがあるが、受信側飽和に弱い | **ネットワーク全体設計と合わせる** |
| Priority & VLAN | 802.1p / 802.1Q タグ付け | VLAN / QoS を使える | タグを打たないので単純な L2 として動く | **VLAN / QoS を使うときだけ意識** |
| VMQ / SR-IOV | Hyper-V / 仮想化向けの NIC 支援 | VM throughput / CPU に効く | 通常ホストとしては単純になる | **Hyper-V ホスト向け** |
| EEE / Green Ethernet | 省電力のための Low-Power Idle | 消費電力は下がるが、レイテンシやリンク相性に影響することがある | 電力は増えるが、安定性で有利なことがある | **速度設定ではなく省電力設定** |
| Selective Suspend / Device Sleep | NIC をアイドル時に低電力化 | 電力が下がる | 復帰安定性は上がることがある | **ノート PC は既定、トラブル時は無効化候補** |
| Wake on Magic Packet / Pattern Match | スリープ中の wake 条件 | 遠隔起動できる | 意図しない wake を防ぎやすい | **必要なときだけ有効** |
| ARP Offload / NS Offload | スリープ中も ARP / NS に NIC が応答 | WoL / Modern Standby 周りの利便性向上 | スリープ中の NIC 処理を減らせる | **スリープ / 管理性が必要なら有効** |
| Network Address | MAC アドレスを上書き | 特殊要件には対応できる | 物理 MAC に戻る | **普段は触らない** |

ここから先は、各設定を順に見ていきます。

## 5. リンクとフレームサイズまわりの設定

### 5.1 Speed & Duplex

これは **リンク速度と全二重 / 半二重の交渉** に関する設定です。  
表示名は `Speed & Duplex`、`Link Speed`、`Link Speed & Duplex` などがあります。

#### 何をしている設定か

Ethernet では、NIC と相手機器（スイッチ、ルータ、他 PC など）が、どの速度・どの duplex で通信するかを決めます。

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
- ただし、**片側だけ固定 / 片側だけ Auto** のような中途半端な状態は事故の元です
- duplex mismatch を起こすと、速度低下、再送、異常な遅延の原因になります

#### どういうとき触るか

触るのは、だいたい次のときです。

- 古い産業機器や古いスイッチとしか繋がらない
- 相手側がすでに固定されている
- Auto でどうしても link が上がらない
- ベンダー指示で明示的な速度固定が必要

#### 実務上の基本方針

**普通は Auto のままでよい** です。  
「1Gbps 出ないから 1Gbps Full に固定」は、見た目は強そうですが、芯を外すことが多いです。

**1Gbps が 100Mbps になる** ときは、まず次を疑います。

- ケーブルの品質
- 8 芯すべての導通
- dock / USB NIC の相性
- スイッチ側ポート
- EEE / Green Ethernet
- ドライバ更新

速度固定は、そのあとです。

### 5.2 Jumbo Packet / Jumbo Frames

これは **標準より大きな Ethernet フレームを使う設定** です。  
表示名は `Jumbo Packet`、`Jumbo Frames`、`Jumbo Packet Size` などがあります。

#### 何をしている設定か

通常の Ethernet は、だいたい **MTU 1500** を前提に動きます。  
Jumbo Frame を有効にすると、**9000 byte 前後** の大きなフレームを使えるようになります。

ただし、ここは名前の罠が多いです。

- ドライバは `9014 Bytes` のように **フレームサイズ** を表示することがある
- OS やツールは `MTU 9000` のように **L3 視点** で見ることがある
- スイッチは **CRC や VLAN タグ込み** で数えることがある

つまり、**9014 と 9000 は別世界の数え方** です。  
数字だけ横並びで見比べると、かなり普通にハマります。

#### 変更するとどう変わるか

**大きくする / 有効にする**

- 大きなデータを送るとき、パケット数が減る
- ヘッダ処理回数が減る
- CPU 使用率が下がりやすい
- wire efficiency が良くなる
- 一方で、**1 パケットあたりの占有時間は長くなる**
- 経路上のどこかが未対応だと drop や fragmentation 問題になる

**標準に戻す / 無効化する**

- 互換性は最も高い
- パケット数は増える
- 大容量転送では CPU / header overhead が増えやすい

#### どういうとき効くか

効きやすいのは、たとえば次です。

- NAS / SMB の大容量コピー
- バックアップ
- 画像 / 映像 / 連続ストリーム転送
- 専用 LAN 上の装置通信
- ストレージ系の大きな連続転送

逆に、**インターネット越し通信** や **途中経路が自分で管理できないネットワーク** では、基本あまり触りません。

#### 使う条件

Jumbo は **end-to-end** で揃って初めて意味があります。

- 自分の NIC
- 相手の NIC
- 途中のスイッチ
- VLAN を噛ませるならタグ分の扱い
- 仮想スイッチやトンネルを使うならその overhead

このどれかが 1500 のままだと、効果が出ないどころか不具合の元になります。

#### 実務上の基本方針

- 専用ネットワークで
- 途中経路を自分で把握できて
- 両端とスイッチを揃えられて
- 実測で benefit が出る

この 4 つが揃うなら有力です。  
逆に、**「よく分からないけど 9014 にしておく」** は危険です。

#### Windows での確認メモ

MTU 9000 を確認したいなら、IPv4 なら次のように `DF` 付き ping を使えます。

```powershell
# 標準 MTU 1500 の確認例
ping <相手IP> -f -l 1472

# MTU 9000 の確認例
ping <相手IP> -f -l 8972
```

`1472` や `8972` は、IP / ICMP ヘッダを差し引いた payload です。  
ただし、**ドライバ UI の 9014 表記と、この ping の数字は一致しません**。ここを混ぜないのが大事です。

### 5.3 Gigabit Master / Slave Mode

これは 1000BASE-T で、**どちらが master、どちらが slave としてクロックを主導するか** に関わる設定です。  
普通の PC ではまず触りませんが、Intel 系 NIC などで出ることがあります。

#### 変更するとどう変わるか

**Auto**

- 通常はこれでよいです
- 相手と自動で役割を決めます

**Force Master / Force Slave**

- 特定の相手機器との link quality が改善することがあります
- ただし、誤ると **link できない、100Mbps に downshift する** などが起きます

#### どういうとき触るか

- 特定の古い相手機器と Gigabit link が不安定
- ベンダーの指示がある
- どうしても auto negotiation 周辺の相性を疑う必要がある

#### 基本方針

**普段は Auto 一択** です。  
これは「性能 tuning」というより、**特殊な link 交渉トラブルを救う設定** だと思ったほうが安全です。

### 5.4 Wait for Link / Link 状態系の設定

`Wait for Link` のような設定は、**ドライバが auto negotiation の成功を待ってから link 状態を報告するか** に関わります。  
`Log Link State Event` のような項目は、link up/down をイベントログに残すための診断用です。

#### Wait for Link の意味

- **On**: 交渉完了を待ってから link を報告しやすい
- **Off**: 待たずに状態を報告する

#### 何が変わるか

- 性能そのものより、**起動時の見え方、failover、初期接続安定性** に効くことがあります
- PXE、古い機器、起動直後のネットワーク依存処理では差が出ることがあります

#### 基本方針

- 通常の PC は既定値のままでよいです
- トラブルシュートでは意味がありますが、まず触る項目ではありません
- `Log Link State Event` は **性能ではなく診断** です

## 6. CPU 負荷、スループット、レイテンシに効く設定

ここが、いちばん「効きそう」に見えて、いちばん雑に触ると危ない帯です。

### 6.1 Checksum Offload

表示名は `IPv4 Checksum Offload`、`TCP Checksum Offload (IPv4/IPv6)`、`UDP Checksum Offload (IPv4/IPv6)` などです。

#### 何をしている設定か

本来 OS がやる **IP / TCP / UDP の checksum 計算や検証** を、NIC ハードウェアに肩代わりさせます。

- 送信時: NIC が checksum を計算してヘッダに入れる
- 受信時: NIC が checksum を検証して、その結果を OS に渡す

#### 変更するとどう変わるか

**有効にする**

- CPU 使用率が下がりやすい
- throughput が上がりやすい
- RSS / RSC / LSO のような他のオフロードとも相性がよい

**無効にする**

- OS が全部計算するので CPU は増えやすい
- 相性問題の切り分けには使いやすい
- packet capture の見え方を整理したいときにも役立つことがあります

#### 実務上の基本方針

これは **原則有効** でよいです。  
実務では、常用で切るより **「相性切り分けのために一時的に切る」** ほうが多いです。

#### よくある勘違い

ローカル PC で packet capture をすると、**送信前の checksum が未計算に見える** ことがあります。  
これは offload の都合でそう見えるだけで、wire 上に出る段階では NIC が正しく計算していることがあります。

さらに重要なのは、**送信側の checksum offload を切っても、LSO が有効なままだと、LSO 経由の送信では checksum 計算が残る** ことがある点です。  
本当に「checksum を全部 OS 側に戻したい」なら、**LSO も切る** 必要があります。

### 6.2 Large Send Offload (LSO) / TSO / Offload TCP Segmentation

表示名は `Large Send Offload v2 (IPv4)`、`Large Send Offload v2 (IPv6)`、`Offload TCP Segmentation` などです。

#### 何をしている設定か

送信側で、OS は大きな TCP データ塊を NIC に渡し、NIC が **MTU に合うサイズへ分割** します。  
TCP の send-heavy な処理を、NIC 側に寄せるイメージです。

#### 変更するとどう変わるか

**有効にする**

- 大きな TCP 送信で CPU 負荷を下げやすい
- throughput が伸びやすい
- 特に大きなファイル送信やサーバ送信で有利

**無効にする**

- OS が細かく分割するので CPU は上がりやすい
- パケットの見え方は単純になる
- 一部のドライバ、VPN、仮想 NIC、フィルタドライバ、ファイアウォール製品との相性問題切り分けには有効

#### 基本方針

通常は **有効** です。  
ただし、次のようなときは一時的に切り分け候補になります。

- 特定の送信だけ遅い
- VPN 経由でおかしい
- filter driver / packet capture との組み合わせで怪しい
- 送信時だけ妙な stalls がある

#### 注意点

Microsoft は、NIC のハードウェア資源が弱い場合、**segmentation offload を有効にすると最大 sustained throughput が下がることがある** としています。  
つまり、「オフロード = 必ず最速」ではありません。  
ただし、それでも CPU を浮かせる価値がある場面は多いので、原則は有効、怪しいときだけ実測で評価、が現実的です。

### 6.3 Receive Segment Coalescing (RSC) / Large Receive Offload

表示名は `Receive Segment Coalescing`、古い表現では `Large Receive Offload` に近い名前で出ることがあります。

#### 何をしている設定か

受信側で、**同じ TCP ストリームの連続セグメントをまとめて OS に渡す** 機能です。  
パケット 1 個ずつではなく、ある程度まとめて処理することで、**ヘッダ処理回数や割り込み処理の overhead** を減らします。

#### 変更するとどう変わるか

**有効にする**

- 受信-heavy な throughput が上がりやすい
- CPU 使用率が下がりやすい
- 小さいパケットが大量に来る場面でも、受信処理を楽にしやすい

**無効にする**

- 1 パケットごとの粒度がそのまま OS に見えやすい
- 低レイテンシ用途では有利になることがある
- packet boundary が見やすくなるので切り分けしやすい
- 受信 throughput は落ちやすい

#### どんなとき効くか

- 受信中心の大容量転送
- サーバの受信処理
- 連続した TCP データ受信

#### どんなとき切る候補か

- レイテンシ最優先
- 小さい request/response を詰めたい
- パケット粒度を見て切り分けたい
- 特定の受信処理との相性が怪しい

#### Hyper-V との関係

物理ホストの NIC が **Hyper-V Virtual Switch に bind されていると、物理ホスト側の RSC は使えない** ことがあります。  
Hyper-V ホストで「RSC を On にしたのに効かない」というときは、この binding 状態を見たほうが早いです。

### 6.4 UDP 系の新しめのオフロード (USO / URO)

最近の NIC や新しめのドライバでは、TCP だけでなく UDP 側にも類似の機能が出てきます。

- **UDP Segmentation Offload (USO)**  
  送信側で大きな UDP データを NIC が分割
- **UDP Receive Offload / UDP RSC / URO**  
  受信側で同一 flow の UDP datagram をまとめて扱う

#### 何が嬉しいか

- 高頻度 UDP 送信 / 受信で CPU を下げやすい
- QUIC のような UDP ベース通信や、特定の高流量 UDP ワークロードで benefit が出ることがある

#### 何に注意するか

- まだ TCP 系オフロードほど「どの環境でも当たり前」ではありません
- ドライバ依存が強いです
- 低レイテンシや解析では、むしろ切ったほうが分かりやすいことがあります

#### 基本方針

普通のデスクトップでは、**出ていなければ無視** で構いません。  
出ている場合も、まずは既定値から入り、UDP heavy な実 workload で差が出るときだけ評価するのがよいです。

### 6.5 Receive Side Scaling (RSS)

表示名は `Receive Side Scaling` です。

#### 何をしている設定か

受信処理を **複数の CPU / コアに分散** します。  
ただし、同じ TCP connection は同じ CPU に寄せるので、順序は保ちやすいです。

#### 変更するとどう変わるか

**有効にする**

- multi-core 環境で受信処理のスケールが良くなる
- 1 コア張り付きのボトルネックを避けやすい
- Web サーバ、ファイルサーバ、大量受信系で効きやすい

**無効にする**

- 処理が単一 CPU に寄りやすい
- 小さな構成では挙動が単純になる
- single-core ではそもそも意味が薄い

#### 実務上の基本方針

**複数コアのマシンでは有効が基本** です。  
今どきの PC / Server で RSS を切る積極的理由は、普通はあまりありません。

#### ただし注意点

- 単一処理装置のシステムでは効果がありません
- 一部の仮想化構成では VMQ が RSS より優先されます
- チーミング構成では、全アダプタで RSS 条件を揃えないと無効化されることがあります

### 6.6 RSS Queues / RSS Processors / RSS Profile

RSS を有効にした上で、さらに **何個の queue / CPU を使うか** を調整できる NIC があります。  
PowerShell だと `Set-NetAdapterRss` で見える項目です。

#### 何をしている設定か

- `RSS Queues`  
  受信キュー数
- `Max RSS Processors`  
  何個の processor を RSS に使うか
- `Base / Max Processor`  
  どの CPU 範囲を使うか
- `RSS Profile`  
  `Closest`、`NUMA`、`Conservative` などの load balancing 方針

#### 変更するとどう変わるか

**queues / processors を増やす**

- 並列度が増える
- 高トランザクション / 高 throughput で有利
- ただし、割り込みや scheduling overhead も増える

**queues / processors を減らす**

- CPU は節約しやすい
- ただし、受信側のスケールが頭打ちになりやすい

#### どう決めるか

ざっくりこう考えると分かりやすいです。

- **1 queue**: CPU を節約したい
- **2 queue**: 一般的なバランス
- **4 以上**: transaction rate が高いサーバ系で有力

ただし、**queue を増やしただけでは full に CPU を使えない** ことがあります。  
RSS の並列度は、queue 数、processor 数、NIC のサポート範囲の掛け算で決まります。

#### プロファイルの意味

細かい話を端折って言うと、次のイメージです。

- `Closest / ClosestStatic`  
  NIC に近い CPU を使いやすい
- `NUMA / NUMAStatic`  
  NUMA を意識して負荷分散
- `Conservative`  
  必要最小限の CPU だけ使って割り込みを減らす

単一ソケットや普通のデスクトップでは、ここを触る必要はほぼありません。  
**NUMA サーバや高負荷サーバで、初めて効いてくる帯** です。

### 6.7 Interrupt Moderation / Interrupt Moderation Rate

表示名は `Interrupt Moderation`、`Interrupt Moderation Rate`、`ITR` などです。

#### 何をしている設定か

NIC がパケットを受けたたびに、すぐ OS に割り込みを投げると、CPU は忙しくなります。  
そこで、**ある程度まとめてから割り込みを出す** のが Interrupt Moderation です。

#### 変更するとどう変わるか

**有効 / 高め / Adaptive**

- 割り込み回数が減る
- CPU 使用率は下がりやすい
- throughput は伸びやすい
- ただし、パケット処理開始が遅れるので **レイテンシは増えやすい**

**無効 / 低め**

- パケットを早く処理しやすい
- 小さいパケットの応答性には有利
- その代わり、CPU と DPC / ISR 負荷は増えやすい

#### 基本方針

- **普通の PC / ファイル転送 / サーバ**  
  → 既定値、Adaptive、Medium から開始
- **低レイテンシ重視**  
  → Low または Off を評価
- **小さいパケットが大量**  
  → 高すぎる moderation は遅延を増やしやすい

#### ありがちな誤解

`Off` にすると「速くなる」と思われがちですが、実際には **CPU を食って全体性能が落ちる** こともあります。  
ここは本当に workload 次第です。

### 6.8 Receive Buffers / Receive Descriptors と Transmit Buffers / Transmit Descriptors

これらは **NIC のリングバッファの深さ** に近い設定です。  
表示名は `Receive Buffers` / `Transmit Buffers`、あるいは `Receive Descriptors` / `Transmit Descriptors` です。

#### 何をしている設定か

NIC は受信 / 送信データを扱うために、内部的にバッファや descriptor ring を持ちます。  
この数が少なすぎると、バーストで流量が増えた瞬間に、NIC が受け止めきれずに drop や stall が起きやすくなります。

#### 変更するとどう変わるか

**増やす**

- burst 耐性が上がる
- sustained throughput が安定しやすい
- 受信 drop や buffer shortage を避けやすい
- その代わり、メモリを消費する
- キューが深くなりすぎると、場合によっては待ち行列遅延が増える

**減らす**

- メモリ消費は減る
- 低レイテンシの一部 workload ではキューが浅いほうが有利なこともある
- ただし、バーストや高 PPS に弱くなる

#### 実務上の使いどころ

次のような場面では、増やす意味があります。

- 受信統計に drop / no buffer / overrun が出る
- 小さいパケットが大量に来る
- 10GbE 以上で burst が強い
- ファイルサーバや中継ノードで queue shortage が疑わしい

一方で、**とりあえず最大値** は雑です。  
低レイテンシ重視なら、むしろ増やしすぎないほうがよいことがあります。

### 6.9 Flow Control

表示名は `Flow Control` です。  
多くの NIC では次のような値を持ちます。

- `Off`
- `Rx Enabled` / `Respond`
- `Tx Enabled` / `Generate`
- `Rx & Tx Enabled` / `Generate and Respond`

#### 何をしている設定か

これは **802.3x pause frame** によるリンクレベルのフロー制御です。  
受信側が「今ちょっと詰まっているので待って」と pause frame を送ることで、相手に送信を一時停止させます。

#### 変更するとどう変わるか

**有効にする**

- 受信側が詰まったときの drop を減らせることがある
- ストレージや大きな burst がある環境で助かることがある
- ただし、**リンク全体を止める** ので、無関係なトラフィックまで巻き込みやすい

**無効にする**

- pause による head-of-line blocking を避けやすい
- tail latency には有利なことがある
- その代わり、受信側が本当に詰まる環境では drop に振れやすい

#### 実務上の基本方針

ここは「NIC だけ」の話ではなく、**スイッチと対向も含めたネットワーク設計の話** です。

- 単純なオフィス LAN  
  → 既定値のままでよいことが多い
- 大きな burst を受ける装置 / ストレージ  
  → 有効が効くことがある
- 低レイテンシ / 混載環境  
  → pause の副作用を嫌って無効評価することがある

**相手やスイッチが pause frame を理解しないなら、NIC だけ有効にしても意味は薄い** です。

#### RDMA との違い

RDMA、特に RoCE では `PFC (Priority Flow Control)` の話が出てきます。  
これは **優先度単位** で止める仕組みで、普通の `Flow Control` より細かい世界です。そこは後で分けて触れます。

## 7. VLAN、QoS、仮想化まわりの設定

ここは「速くなる設定」ではなく、**ネットワークの役割や構成を変える設定** が多い帯です。

### 7.1 Priority & VLAN / Packet Priority & VLAN / NDIS QoS

表示名は NIC ベンダーごとにかなり揺れます。

- `Priority & VLAN`
- `Packet Priority & VLAN`
- `VLAN ID`
- `NDIS QoS`
- `Priority VLAN`

#### 何をしている設定か

ここで扱っているのは主に次の 2 つです。

- **802.1Q VLAN タグ**  
  どの VLAN に属するフレームかを示す
- **802.1p 優先度タグ**  
  フレームに優先度を持たせる

#### 変更するとどう変わるか

**有効にする / VLAN ID を設定する**

- ホストを特定 VLAN に所属させられる
- スイッチ側の VLAN 設計に合わせられる
- QoS / DCB の材料になる
- ただし、誤ると **見事にネットワークから消える** ことがあります

**無効にする**

- 普通の untagged Ethernet として動作します
- VLAN を使っていないネットワークでは、こちらが普通です

#### 基本方針

- **VLAN を使っていないなら触らない**
- **QoS / DCB を使っていないなら、優先度も不用意に触らない**
- **「何となく On」は危険**

この設定は、**直接的に throughput を増やす設定ではありません**。  
役割を変える設定です。

#### よくあるハマりどころ

- NIC で VLAN タグを打っているのに、スイッチ側ポートが access で受けている
- スイッチ側は trunk なのに、NIC 側は untagged 前提
- ホスト OS、Hyper-V vSwitch、NIC driver のどこで VLAN を扱うべきか混ざっている

このへんは、設定をいじるほど賢くなるというより、**設計を一枚で整理したほうが早い** 帯です。

### 7.2 VMQ / VMMQ / SR-IOV

これは **Hyper-V や仮想化ホスト向け** の設定です。

- `VMQ`  
  Virtual Machine Queue
- `VMMQ`  
  Virtual Machine Multi-Queue
- `SR-IOV`  
  Single Root I/O Virtualization

#### VMQ の意味

VMQ は、NIC が受信パケットを見て、**どの VM 向けかをハードウェアで振り分ける** 仕組みです。  
これにより、ホスト CPU のソフトウェア処理を減らしやすくなります。

#### VMMQ の意味

VMMQ は VMQ の拡張で、**1 VM あたり複数 queue** を使って、さらに並列度を上げやすくするものです。  
高トラフィック VM を複数抱えるときに効きます。

#### SR-IOV の意味

SR-IOV は NIC の仮想機能を VM に直接見せることで、**Hyper-V のソフトウェアスイッチの一部を迂回** し、より native に近い性能を狙うものです。

#### 変更するとどう変わるか

**有効にする**

- VM の throughput / latency / CPU 効率が改善することがある
- 仮想化ホストの負荷を下げやすい
- ただし、BIOS、NIC、ドライバ、Hyper-V、vSwitch 設計の整合が必要

**無効にする**

- 構成は単純になる
- 仮想化支援の benefit は減る

#### 基本方針

- **Hyper-V ホストなら評価対象**
- **普通のデスクトップ / ノートなら、だいたい無関係**
- **「RSS が大事だから VMQ は関係ない」は早計**

仮想化ホストでは、**ホストの TCP/IP 処理** と **VM 向けの仮想スイッチ処理** で、効く設定が違います。  
ここを desktop NIC の感覚でまとめて語ると、話がぐちゃっとしやすいです。

### 7.3 RDMA / DCB / PFC は別世界

このへんは NIC の Advanced タブに出ることもありますが、普通の PC で触る帯ではありません。

- **RDMA**  
  CPU をあまり介さずにメモリアクセスする高速通信
- **DCB (Data Center Bridging)**  
  データセンター向けの Ethernet 制御群
- **PFC (Priority Flow Control)**  
  優先度単位の pause
- **ETS**  
  帯域配分の制御

#### どんな世界か

- SMB Direct
- Storage Spaces Direct
- Hyper-V クラスタ
- RoCE / iWARP
- 高速ストレージ / 東西トラフィック

この世界では、**NIC だけでなくスイッチの QoS / PFC 設計まで含めて揃っている** 必要があります。  
片方だけ雑に有効化すると、速くなるどころか、むしろ苦しくなります。

#### 基本方針

**RDMA 要件が明示されていないなら、触らない** でよいです。  
ここは「ちょっと速くしたい」人向けの knob ではありません。完全に設計案件です。

## 8. 省電力、スリープ、Wake on LAN まわりの設定

ここは speed tuning と見せかけて、実態は **電力 / 復帰 / 管理性** の設定が多いです。

### 8.1 Energy Efficient Ethernet (EEE) / Green Ethernet

表示名は `Energy Efficient Ethernet`、`EEE`、`Green Ethernet` などです。

#### 何をしている設定か

EEE は、トラフィックが途切れた瞬間に、リンクを **Low-Power Idle** に入れて消費電力を下げる仕組みです。

#### 変更するとどう変わるか

**有効にする**

- 消費電力が下がる
- ノート PC や常時接続機器で意味がある
- ただし、**少しの遅延** が増えることがある
- 古いスイッチや質の悪いケーブルでは、リンク不安定や速度 downshift のきっかけになることがある

**無効にする**

- 電力は増える
- その代わり、リンクの安定性や低レイテンシで有利なことがある

#### 実務上の基本方針

- ノート PC / 一般用途  
  → 既定値のままでもよい
- 低レイテンシ / 産業装置 / 100Mbps に落ちる / リンク不安定  
  → **まず切り分け候補**
- 10GbE 以上の安定性重視  
  → 省電力より安定を取り、無効評価することがある

EEE は **両端の対応と auto negotiation** が前提です。  
片側や周辺機器との相性が怪しいとき、真っ先に疑われる設定のひとつです。

### 8.2 Selective Suspend / Device Sleep / Standby 時リンク制御

表示名は次のように揺れます。

- `Selective Suspend`
- `NS Offload for WoWLAN` のような派生項目
- `System Idle Power Saver`
- `Device Sleep on Disconnect`
- `Reduce link speed during standby`
- `Ultra Low Power Mode`
- `Low Power on Media Disconnect`

#### 何をしている設定か

要するに、**アイドル時やスリープ時に NIC をどこまで眠らせるか** を決める設定です。

#### 変更するとどう変わるか

**有効にする**

- 消費電力は下がる
- ドック接続やバッテリー運用では意味がある
- ただし、スリープ復帰後の NIC 消失、USB NIC 再認識失敗、最初の数秒だけ通信不安定、のような問題を起こすことがある

**無効にする**

- 電力は増える
- 復帰時の挙動は単純になりやすい
- 特に USB Ethernet や dock では安定化することがある

#### 基本方針

- **ノート PC では既定値から開始**
- **復帰トラブルがあるなら最初に疑う**
- **装置制御 PC や 24/7 運用では、むしろ切るほうが分かりやすい**

省電力は正義ですが、現実にはドライバと firmware が寝ぼけることがあります。  
そこは機械なので、普通にあります。

### 8.3 Wake on Magic Packet / Wake on Pattern Match

これはスリープ中の PC を、ネットワーク経由で起こすための設定です。

- `Wake on Magic Packet`
- `Wake on Pattern Match`
- `Wake on Link`
- `Wake on Media Disconnect`
- `S0ix Wake on Magic Packet`

#### Wake on Magic Packet の意味

これは **対象 NIC の MAC アドレスを 16 回並べた特定のパターン** を含むパケットを受けたときに、PC を wake させる仕組みです。  
Wake on LAN を欲しいだけなら、だいたいこれが本命です。

#### Wake on Pattern Match の意味

Magic Packet より広く、**特定の通信パターンに合致したとき起こす** 仕組みです。  
便利なことはありますが、ARP や近いパターンで **意図しない wake** を招きやすいです。

#### 変更するとどう変わるか

**Magic Packet を有効にする**

- 遠隔起動に使える
- 意図しない wake は比較的少ない

**Pattern Match まで有効にする**

- より広い条件で起こせる
- そのぶん誤起床しやすい

#### 基本方針

- **Wake on LAN が必要なら Magic Packet を有効**
- **不要なら無効**
- **Pattern Match は必要性が明確なときだけ**

なお、これらは **BIOS / UEFI 側の WoL 設定** や、**Power Management タブ** の設定と組み合わせで効きます。  
NIC だけ On にしても起きないことは普通にあります。

### 8.4 ARP Offload / NS Offload

これは、スリープ中でも NIC が最低限の応答を肩代わりする設定です。

- `ARP Offload`
- `NS Offload`  
  (`NS` は IPv6 の Neighbor Solicitation)

#### 何をしている設定か

PC 本体を起こさずに、NIC が **ARP / Neighbor Discovery に応答** することで、ネットワーク上の存在感をある程度保ちます。

#### 変更するとどう変わるか

**有効にする**

- Modern Standby や WoL 周りの利便性が上がる
- スリープ中も NIC が最低限の返答をしてくれる
- 管理系機能と相性がよい

**無効にする**

- スリープ中の NIC の仕事を減らせる
- ただし、スリープ中の到達性や wake 条件で不便になることがある

#### 基本方針

通常は **有効 / 既定値** でよいです。  
これを常用で切る理由は少なく、**スリープ周りの相性切り分け** で一時的に触ることが多い項目です。

### 8.5 Power Management タブの設定

Advanced タブとは別に、NIC のプロパティには **Power Management** タブがあります。  
ここも地味に重要です。

よく見るのは次の 3 つです。

- **Allow the computer to turn off this device to save power**
- **Allow this device to wake the computer**
- **Only allow a magic packet to wake the computer**

#### 「Allow the computer to turn off this device to save power」の意味

この項目は、ざっくり「NIC の電源管理を Windows にどこまで任せるか」です。  
有効にすると、Windows は NIC を低電力状態に入れてから復帰させます。  
無効にすると、スリープ時にデバイスを停止し、復帰時に再初期化する動きになります。

実務では、**ドライバが低電力遷移に弱い** とき、このチェックを外すと復帰が安定することがあります。

#### Wake 系の基本方針

- リモート起動したい  
  → `Allow this device to wake the computer` を有効
- 誤起床を避けたい  
  → `Only allow a magic packet to wake the computer` も有効
- Wake on LAN 自体が不要  
  → wake 系は全部無効

## 9. そのほかの、よく見るが触る機会は少ない設定

### 9.1 Network Address / Locally Administered Address

これは **MAC アドレスを手動で上書きする** 設定です。

#### 何に使うか

- ラボ環境で MAC を固定したい
- 特定装置とのテストで MAC を揃えたい
- 旧構成からの移行で、MAC ベースの制御を一時的に合わせたい

#### 注意点

- 同一セグメントに **重複 MAC** を作ると普通に壊れます
- multicast アドレスや、全 0、全 F のような値は使うべきではありません
- 元に戻すときは、値を空にして既定値へ戻します

#### 基本方針

**普段は触らない** でよいです。  
これは性能設定ではありません。身元偽装のためのつまみです。

### 9.2 Adaptive Inter-Frame Spacing

かなり古参の設定です。  
もともとは **衝突が多い Ethernet 環境で、フレーム間隔を調整して救う** ためのものです。

#### 今どう考えるか

現代の switched full-duplex Ethernet では、まず主役ではありません。  
半二重や collision を前提にした時代の匂いがかなり残っています。

#### 基本方針

- **現代の普通の LAN では既定値のまま**
- **古い装置や特殊環境でベンダー指示があるときだけ** 触る

### 9.3 Header Data Split

これは主にサーバ向けで、**パケットヘッダと payload を分けて扱う** ことで CPU 処理を助ける類いの設定です。

#### 何が起きるか

適したワークロードでは CPU 効率が良くなることがありますが、万能ではありません。  
最近の一般的な client NIC では、そもそも意識する機会が少ないです。

#### 基本方針

- **サーバ向け / 特定ワークロード向け**
- **一般クライアントでは既定値のまま**
- **ベンダー資料と workload が一致するときだけ評価**

### 9.4 Low Latency Interrupts

ベンダーによっては `Low Latency Interrupts` のような項目があります。  
これは、遅延に敏感なパケットをより早く処理する方向の、**割り込み制御の特殊版** だと思えば大きく外しません。

#### 変更するとどう変わるか

**有効にする**

- 特定 workload で latency が改善することがある
- その代わり、CPU / ISR / DPC 負荷は増えやすい

**無効にする**

- 挙動は単純になりやすい
- throughput や CPU 効率を優先しやすい

#### 基本方針

これは **測って勝つときだけ使う** 項目です。  
雰囲気で On にする帯ではありません。

### 9.5 TCP Chimney Offload / IPsec Task Offload などの古い項目

古めの NIC や古いドライバでは、次のような項目を見ることがあります。

- `TCP Chimney Offload`
- `IPsec Task Offload`
- `Task Offload` 系の古い表現

#### 基本方針

**今は触らない、使わない** が正解です。  
Windows Server 2016 以降では、これらは非推奨 / 廃止系で、Microsoft も使わないよう案内しています。

## 10. 目的別のざっくり指針

ここでは、用途ごとの「最初の形」をざっくり置きます。  
唯一の正解ではありませんが、初手としては悪くないラインです。

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
- Receive/Transmit Buffers: **drop があるなら少し増やす**
- Interrupt Moderation: **既定値 / やや高め**
- EEE: **安定性重視なら無効評価**

大きな転送では、**パケット数削減、CPU 削減、queue 不足回避** が効きやすいです。

### 10.3 産業用カメラ / 装置制御 / 低レイテンシ重視

- Speed & Duplex: **Auto を基本。必要なら相手に合わせて固定**
- Jumbo: **カメラ / NIC / スイッチが揃うなら評価**
- Checksum Offload: **まず有効**
- LSO: **送信相性が怪しければ一時的に無効評価**
- RSC: **レイテンシや観測を優先するなら無効候補**
- Interrupt Moderation: **Low / Off を評価**
- Buffers: **増やしすぎない**
- Flow Control: **pause の副作用を要評価**
- EEE / Green Ethernet: **無効候補**
- Selective Suspend / 電力管理: **無効候補**

低レイテンシ帯では、**throughput 最適化の設定が必ずしも有利ではない** というのが面白くて厄介です。

### 10.4 Hyper-V ホスト

- VMQ / VMMQ / SR-IOV: **構成に応じて評価**
- RSS: **ホスト側トラフィックには重要**
- RSC: **物理 NIC が vSwitch に bind されている場合は制約あり**
- QoS / VLAN: **vSwitch 設計と合わせる**
- Flow Control / PFC: **ストレージ / RDMA 設計と一体で考える**

これは desktop tuning ではなく、**仮想化基盤設計** です。  
単体の NIC だけ見ても正解は出ません。

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

切り分けでは、**性能最適化より、挙動の単純化** が勝ちます。

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
- Receive/Transmit Buffers
- Jumbo Frame（専用経路なら）
- NIC 統計の drop / error

これは **throughput 系の問題** なので、Jumbo や queue、オフロードが効きやすいです。

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

### 12.6 実務メモ

- 一部の設定は **アダプタの無効 / 有効** や再起動が必要です
- DisplayName がローカライズされている場合があります
- 同じベンダーでも driver version で項目名が変わることがあります
- PowerShell で自動化するなら、**実機の値を先に列挙してから** 書くほうが安全です

## 13. まとめ

Windows の NIC 詳細設定は、項目名だけ見ると全部「強そう」です。  
でも実際には、**throughput、latency、CPU、power、compatibility のどれを取るかで正解が変わる** 世界です。

この記事の要点を一気に言うと、こうです。

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
ただし、目的が合っていれば、かなり効きます。逆に、目的がズレると、かなり素直に裏目を引きます。ネットワークは変に律儀です。

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
- Intel Support: 速度固定、Jumbo、Interrupt Moderation、EEE、WoL などは NIC 型番ごとのサポート記事から確認  
  ※ Intel のサポート構成は時々統合・再編されるので、該当 NIC 型番から辿るのが安全です

## 関連トピック

- [技術トピック](https://comcomponent.com/topics/)
- [不具合調査 / 長期稼働テーマ](https://comcomponent.com/topics/)
- [Windows ソフト開発に関するブログ一覧](https://comcomponent.com/blog/)

## このテーマの相談先

NIC 設定は、単体のつまみとして見るより、**通信経路、アプリの送受信パターン、長期稼働条件、ログ設計** とまとめて見たほうが、原因に早く当たります。

- [不具合調査・原因解析](https://comcomponent.com/services/bug-investigation/)
- [技術相談・設計レビュー](https://comcomponent.com/services/technical-consulting/)

## 著者プロフィール

- [小村 豪](https://comcomponent.com/profile/go-komura/)
