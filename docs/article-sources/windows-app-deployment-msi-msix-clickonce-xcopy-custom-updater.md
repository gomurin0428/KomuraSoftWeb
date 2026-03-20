---
title: "Windows アプリの配布方式をどう選ぶか - MSI / MSIX / ClickOnce / xcopy / 独自 updater の判断表"
date: 2026-03-20T10:00:00+09:00
author: "小村 豪"
tags:
  - Windows
  - 配布
  - MSI
  - MSIX
  - ClickOnce
  - xcopy
  - updater
description: "Windows アプリの配布方式は、インストーラの形式ではなく、OS との結合度と更新責任の選択です。MSI / MSIX / ClickOnce / xcopy / 独自 updater を、企業内運用、閉域環境、サービス・ドライバ、頻繁な更新の観点で整理します。"
---

Windows アプリの配布方式を決める場面では、つい「どれが新しいか」「どれが簡単か」で話を始めがちです。  
ただ、実務で本当に効くのは別の軸です。

- 利用者単位で入れたいのか、マシン全体へ入れたいのか
- 更新を配布基盤に任せたいのか、自前で持ちたいのか
- サービス / ドライバ / shell extension / COM 登録のような OS 統合があるのか
- 閉域・オフライン・USB 配布に耐える必要があるのか
- package identity が要るのか、それとも素の Win32 として unrestricted に動かしたいのか[^2][^12]

ここで危ないのは、次のような選び方です。

- 新しいから MSIX
- 昔からあるから MSI
- 自動更新が欲しいから、とりあえず独自 updater
- インストーラが面倒だから、全部 xcopy

配布方式の選択は、**インストーラ形式の好み** ではなく、  
**OS にどこまで触るか** と **更新責任を誰が持つか** の選択です。

この記事では、Windows アプリの実務向けに、MSI / MSIX / ClickOnce / xcopy / 独自 updater を判断表として整理します。

## 目次

1. まず結論
2. 5 つは同じ土俵ではない
3. 一枚で見る判断表
4. 観点別の比較表
5. それぞれ、どういう案件に向くか
   - 5.1 MSI
   - 5.2 MSIX
   - 5.3 ClickOnce
   - 5.4 xcopy
   - 5.5 独自 updater
6. 迷いやすい論点
   - 6.1 package identity が要るか
   - 6.2 サービス / ドライバ / shell extension があるか
   - 6.3 per-user か per-machine か
   - 6.4 更新頻度と運用責任
   - 6.5 閉域・オフライン配布
7. 迷ったときに最後に見る 6 問
8. まとめ
9. 参考資料

## 1. まず結論

かなり雑に、でも実務で使いやすく言うとこうです。

- **マシン全体に入れる、サービスや COM 登録、前提物の導入がある** なら、まずは **MSI** を起点に考えます。Windows Installer は per-machine / per-user の installation context を持ち、transaction と rollback、services configuration まで扱えます。[^1]
- **Windows 10/11 前提で、clean install / clean uninstall、頻繁な更新、package identity が欲しい** なら、**MSIX** が有力です。package identity は notifications、background tasks、custom context menu extensions などの Windows 機能の前提になります。[^2][^3]
- **.NET の社内向けデスクトップアプリを、利用者単位で簡単に配って自動更新したい** なら、**ClickOnce** は今でもかなり強いです。自己更新型で、最小限のユーザー操作で入れられます。[^4]
- **置くだけで動くツール、閉域、USB 配布、管理者権限なし** を優先するなら、**xcopy** がいちばん素直です。自己完結していて、レジストリ登録や依存を必要としない構成なら特に強いです。[^5]
- **更新 UX、チャネル、段階展開、telemetry、復旧戦略まで自分たちで握りたい** なら、**独自 updater** です。ただし、自由度ではなく責任が増えます。
- **ドライバが必要** なら、最初から MSIX 中心で考えないほうが安全です。MSIX は driver をサポートしません。[^10]
- **Explorer の in-process shell extension が必要** なら、MSIX は向きません。shell extension はサポートされません。[^8]

要するに、だいたい次です。

1. **OS への登録が濃い** → MSI 寄り  
2. **package identity と modern packaging を取りたい** → MSIX  
3. **per-user の簡単配布と built-in 更新が欲しい** → ClickOnce  
4. **置くだけ配布が最優先** → xcopy  
5. **更新基盤を自社で設計・運用する覚悟がある** → 独自 updater

## 2. 5 つは同じ土俵ではない

ここはかなり大事です。

**MSI / MSIX / ClickOnce / xcopy** は、主に **どう入れるか** の話です。  
一方で **独自 updater** は、主に **どう更新責任を持つか** の話です。

つまり、実務では 2 層に分けて考えたほうが整理しやすいです。

| 層 | 主な候補 | 決めること |
|---|---|---|
| 初回導入 | MSI / MSIX / ClickOnce / xcopy | どこへ配置するか、何を登録するか、権限、アンインストール |
| 継続更新 | MSIX App Installer / ClickOnce / 手動差し替え / 独自 updater | 更新確認、配信元、署名検証、rollback、チャネル、UI |

なので、**独自 updater は最初に選ぶものではなく、既存の配布方式で足りない更新要件があるときに追加で選ぶもの** だと思ったほうがぶれません。

たとえば、

- xcopy + 独自 updater
- MSI + 独自 updater
- 初回導入は MSI、以後はアプリ内 updater
- MSIX + App Installer

のように、**初回導入と継続更新の方式は別々に決める** ことがよくあります。

## 3. 一枚で見る判断表

まずは、いちばん実務で使いやすい表を置きます。

| 状況 | まず選ぶもの | 理由 |
|---|---|---|
| 全ユーザー向けで、サービス、COM 登録、machine-wide な設定がある | MSI | Windows Installer の土俵に素直に乗るほうが事故が少ない |
| Windows 10/11 前提で、clean install / uninstall、頻繁な更新、package identity が欲しい | MSIX | modern packaging と update モデルに寄せやすい |
| .NET の社内業務アプリを per-user で簡単配布したい | ClickOnce | 自己更新が標準で、導入の心理的コストが低い |
| 置くだけで動くツール、閉域、USB、管理者権限なし | xcopy | インストールという概念をできるだけ持ち込まない |
| 商用製品で、更新 UX・チャネル・段階配信を自分たちで握りたい | 独自 updater | built-in 更新より自由度が高い |
| ドライバが必要 | MSI か専用 installer 寄り | driver package は別問題で、MSIX は不向き |
| in-process shell extension が必要 | MSI か専用 installer 寄り | MSIX では shell extension がサポートされない |
| Windows service はあるが、対象 OS を 2004+ 以降に限定でき、admin install も許容できる | MSI か MSIX を比較 | MSIX でも service は扱えるが、OS 条件と制約を必ず確認する[^9] |

この表でいちばん大事なのは、**「更新がある」だけで独自 updater に飛ばない** ことです。

- 更新を OS / 配布基盤に任せるのか
- 更新をアプリ製作者が全部背負うのか

ここはコスト差がかなり大きいです。

## 4. 観点別の比較表

ここは公式な優劣表ではなく、かなり実務寄りです。

| 観点 | MSI | MSIX | ClickOnce | xcopy | 独自 updater |
|---|---|---|---|---|---|
| per-user 導入のしやすさ | ○ | ○ | ◎ | ◎ | ○ |
| per-machine 導入のしやすさ | ◎ | ○ | △ | × | ○ |
| 自動更新を素で持つ | △ | ◎ | ◎ | × | ◎ |
| package identity を取れる | × | ◎ | × | × | × |
| サービスとの相性 | ◎ | △ | × | × | ○ |
| ドライバとの相性 | △ | × | × | × | ○ |
| shell extension との相性 | ◎ | × | × | × | ○ |
| 閉域・オフライン配布 | ◎ | ○ | ○ | ◎ | ◎ |
| 既存レガシー Win32 との相性 | ◎ | △〜○ | ○ | ◎ | ○ |
| 実装・運用コスト | ○ | ○ | ◎ | ◎ | × |
| 更新 UX の自由度 | △ | ○ | △ | × | ◎ |

見方のコツは、**何が最強か** ではなく、**何がいちばん摩擦が少ないか** です。

たとえば、

- サービスを入れる
- 全ユーザー向けに入れる
- Program Files 配下へ入れる
- レジストリや前提物を含めて machine state を作る

なら、MSI は今でもかなり自然です。

逆に、

- notifications
- background tasks
- custom context menu extensions
- share targets
- clean update / clean uninstall

のように **package identity** が効く機能や modern packaging の恩恵を取りたいなら、MSIX の意味が大きくなります。[^2]

## 5. それぞれ、どういう案件に向くか

### 5.1 MSI

MSI は、**「Windows の伝統的なデスクトップアプリを、ちゃんと install / uninstall / repair したい」** ときの基準点です。Windows Installer は desktop style application 向けで、transaction / rollback、per-machine / per-user、services configuration まで持っています。[^1]

特に向いているのは、たとえば次のようなものです。

- 全ユーザー向けの業務アプリ
- Windows サービスを含むアプリ
- COM 登録、file association、machine-wide な設定を伴うアプリ
- 既存の installer 運用が既にある製品
- 更新頻度はそこまで高くなく、管理部門が導入タイミングを握りたい案件

MSI の強みは、**「アプリを OS にどう入れたか」を Windows の流儀で表現しやすい** ことです。  
インストール、修復、アンインストールの筋が通りやすく、サポート時の説明も比較的しやすいです。

一方で、弱いところもはっきりしています。

- authoring が地味に難しい
- upgrade / patch の設計を雑にすると後で苦しみやすい
- custom action を増やすほど壊れやすい
- 高頻度更新の製品では、更新 UX が重たくなりやすい

なので MSI は、**「OS への導入をきちんと管理したい」案件には強いが、「毎週気軽に更新したい」案件ではやや重い**、くらいに見ると実務的です。

なお、**driver がある案件では、driver package 自体の扱いを先に決める** ほうが大事です。  
MSI が全体の bootstrapper にはなれても、driver は driver の土俵で考える必要があります。

### 5.2 MSIX

MSIX は、**「Windows が管理しやすい packaging / update モデルに寄せる」** 選択です。  
clean install / uninstall、差分更新、App Installer による配布、package identity が大きな魅力です。[^2][^3][^7]

特に向いているのは、たとえば次です。

- Windows 10/11 を前提にできるデスクトップアプリ[^11]
- 更新頻度が高めの業務アプリ
- package identity が必要な Windows 機能を使いたいアプリ[^2]
- Intune / PowerShell / double-click install など modern な配布経路に寄せたい案件[^11]
- clean uninstall を重視する案件
- WinUI 3 / Windows App SDK packaged app と相性のよい案件

MSIX の強みは、**「更新とアンインストールのきれいさ」** と **「package identity を取れること」** です。  
App Installer を使えば、web / network share / local file share からの配布と更新もできます。[^7]

また、MSIX は **in-place に OS を汚しにくい** 前提で設計されているので、昔ながらの「installer が HKLM や install directory を好きに触る」流儀からは少し考え方が変わります。legacy app を MSIX 化するときは、AppData / registry / install directory に対する前提を先に確認しておいたほうが安全です。[^10]

ただし、ここを雑に見ると事故ります。

- **driver はサポートされません**[^10]
- **in-process shell extension はサポートされません**[^8]
- **service は扱えますが、Windows 10 version 2004 以降などの OS 条件と admin install が前提になります**[^9]
- **古い Win32 アプリの前提をそのまま持ち込むと、virtualization / redirection で詰まりやすい**[^10]

なので MSIX は、  
**「今の Windows の packaging model に寄せる意思があるか」**  
を先に問う方式です。

「とりあえず新しいから MSIX」ではなく、

- 対象 OS はそろっているか
- package identity の価値はあるか
- legacy な前提を書き換えられるか

を見て決めるほうがうまくいきます。

### 5.3 ClickOnce

ClickOnce は、**「.NET の Windows デスクトップアプリを、利用者単位で軽く配って軽く更新する」** ところに強みがあります。自己更新型で、最小限のユーザー操作で導入でき、web / network share / removable media から publish できます。[^4][^13]

特に向いているのは、次のようなものです。

- 社内向けの WinForms / WPF アプリ
- 利用者単位の業務ツール
- 管理者権限をなるべく避けたい案件
- installer authoring に時間をかけたくない案件
- 更新は欲しいが、独自 updater までは持ちたくない案件

ClickOnce のいちばん大きい利点は、**「配って終わり」ではなく、「更新まで込みで簡単」** なことです。  
update location や minimum required version を持てるので、社内ツールにはかなり噛み合います。[^6]

ただし、万能ではありません。

- 基本的に **.NET の desktop app** の世界です
- **service / driver / shell extension / machine-wide な導入** には向きません
- 配布状態は ClickOnce cache に寄るので、普通の installer とは感覚が違います[^14]
- **.NET Framework 時代に比べると、modern .NET では一部の update API や「起動後バックグラウンド更新」周りがそのままでは使えない** 点があります[^6]

なので ClickOnce は、  
**「社内向け .NET アプリを、per-user で、素早く、更新込みで回したい」**  
ときに強い方式です。

逆に、OS へ深く触るタイプの製品や、複数前提物を束ねた installer 的な役割までは期待しないほうが安全です。

### 5.4 xcopy

xcopy は、**「install ではなく deploy」** です。  
レジストリ登録も、修復機能も、package identity もありません。その代わり、**置くだけで済む** なら最強クラスに単純です。[^5]

特に向いているのは、たとえば次です。

- 診断ツール
- 装置設定ツール
- ログ収集ツール
- 現場へ USB で渡すユーティリティ
- 閉域ネットワーク向けの小さめの補助アプリ
- side-by-side で複数バージョンを共存させたいケース

また、Windows App SDK の self-contained / unpackaged 構成では、依存物が `.exe` の隣へコピーされ、xcopy deploy や custom installer に載せられることが公式に案内されています。[^15]

xcopy の強みは、**失敗の仕方が分かりやすい** ことです。

- フォルダを丸ごと差し替える
- バージョン別フォルダで共存させる
- 戻したければ前のフォルダへ戻す

という運用がしやすいです。

ただし、当然ながら弱いところもあります。

- Start menu / ARP / repair がない
- file association / service / shell extension / driver は別問題
- 更新は手動か、別スクリプトか、別 updater が要る
- mutable data を exe の横へ置く設計だと、配置先次第で困りやすい

つまり xcopy は、  
**「OS に何も登録しない代わりに、運用もなるべくシンプルにする」**  
方式です。

アプリが本当に自己完結していて、  
**置けば動く / 消せば消える**  
を守れるなら、xcopy はかなり強いです。

### 5.5 独自 updater

独自 updater は、**自由度の選択** というより **責任の選択** です。

特に向いているのは、たとえば次のような製品です。

- 更新頻度が高い
- stable / beta / preview などのチャネルを持ちたい
- 段階配信やロールアウト率を制御したい
- 背景ダウンロード、ユーザー通知、メンテナンス時間帯を細かく制御したい
- 更新 telemetry や crash recovery を自前で見たい
- ClickOnce や MSIX の UX / 制約では足りない

独自 updater の強みは、もちろん大きいです。

- 更新 UX を完全に決められる
- サーバー側の manifest 設計を自由にできる
- 差分配信、チャネル、kill switch、rollback を自前で組める
- xcopy ベースでも、製品らしい更新体験を作れる

ただし、支払うものも大きいです。

- 署名検証
- 配信 manifest
- 再試行 / resume
- proxy / firewall / 閉域対応
- rollback
- 壊れた更新の復旧
- updater 自身の更新
- 起動中ファイルの置換
- サポート窓口での切り分け

この全部が、自分たちの責任になります。

なので独自 updater は、

- 製品規模がある
- 継続運用の予算がある
- 更新自体が製品価値に近い

という条件がそろって初めて強いです。

社内ツールや小さめの業務アプリであれば、  
**まず MSIX / ClickOnce / xcopy + 手順化 で足りないか**  
を確認してからで十分なことがかなり多いです。

## 6. 迷いやすい論点

### 6.1 package identity が要るか

ここはかなり大きな分岐です。

もし欲しいのが、

- notifications
- background tasks
- custom context menu extensions
- share targets

のような **package identity 前提の Windows 機能** なら、MSIX の価値が一気に上がります。[^2]

逆に、

- unrestricted な file system access
- unrestricted な registry access
- elevation / process model の自由度
- 古い Win32 的な前提をそのまま残したい

なら、unpackaged 寄りの方式のほうが自然です。[^12]

### 6.2 サービス / ドライバ / shell extension があるか

この 3 つは、配布方式を一気に重くします。

- **driver**: MSIX では不可[^10]
- **in-process shell extension**: MSIX では不可[^8]
- **Windows service**: MSI は自然、MSIX でも可能だが target OS と admin install 条件を必ず確認[^9]

つまり、OS と深く結びつく要素があるほど、  
**「見た目が簡単な配布」より「正しく導入・更新・削除できるか」** が主題になります。

### 6.3 per-user か per-machine か

ここを曖昧にしたまま進めると、あとで必ず揉めます。

- **per-user** に寄せたい  
  - ClickOnce  
  - xcopy  
  - 一部の MSIX
- **per-machine** に寄せたい  
  - MSI  
  - 条件が合えば MSIX

「管理者権限なしで入れたい」と  
「全ユーザーが同じ場所から使いたい」は、同じではありません。

### 6.4 更新頻度と運用責任

更新頻度の感覚で見ると、ざっくりこうです。

- **四半期〜月次更新**: MSI でも十分回る
- **月次〜週次更新**: MSIX / ClickOnce がかなり楽
- **週次〜日次更新**: 独自 updater を検討する理由が出てくる
- **更新は手動でよい / 配置側が制御する**: xcopy でも十分

配布方式は、**技術選定** であると同時に **運用設計** でもあります。

### 6.5 閉域・オフライン配布

閉域では、きれいな auto-update より **単純さ** が勝つことが多いです。

- xcopy は強い
- MSI も強い
- ClickOnce も file share / removable media で使える[^13]
- MSIX も App Installer で web / network share / local file share を使えます[^7]

ただし、閉域で頻繁に更新するなら、  
「誰が、どこへ、新版を置き、旧版をどう残すか」  
まで決めないと、方式だけ選んでも運用が崩れやすいです。

## 7. 迷ったときに最後に見る 6 問

最後に、実務でかなり効く 6 問だけ置きます。

1. **そのアプリは current user だけでよいか、machine-wide に入れる必要があるか**
2. **service / driver / shell extension / COM 登録はあるか**
3. **package identity が必要な Windows 機能を使うか**
4. **標準ユーザーだけで導入したいか**
5. **更新頻度は月次か、週次か、もっと高いか**
6. **対象環境は閉域か、OS バージョンはそろっているか**

この 6 問に答えるだけで、だいたい次に落ちます。

- 2 が **はい** → まず MSI 側から考える  
  - ただし service は recent Windows なら MSIX も比較  
  - driver は MSIX を外す
- 3 が **はい** → MSIX を優先検討
- 1 が **current user**、4 が **はい**、かつ .NET desktop app → ClickOnce が有力
- 4 が **はい**、2 が **いいえ**、置くだけ運用でよい → xcopy が有力
- 5 が **高い**、更新 UX を製品価値として握りたい → 独自 updater を比較対象へ入れる

## 8. まとめ

Windows アプリの配布方式は、次の一文にかなり集約できます。

> **初回導入をどう成立させるか** と  
> **継続更新を誰が責任を持って回すか** を分けて決める。

そのうえで、ざっくりした実務判断はこうです。

- **MSI**: OS へ深く入れる伝統的 desktop app
- **MSIX**: package identity と modern packaging / update を取りたい app
- **ClickOnce**: per-user の .NET 社内アプリを簡単に配って更新したい
- **xcopy**: 置くだけでよい自己完結ツール
- **独自 updater**: 更新自体を自社で設計・運用する覚悟がある製品

そして、いちばん大事なのはこれです。

- **driver / shell extension / service** があるなら、配布方式は最後の見た目ではなく、OS 統合の方式から決まる
- **package identity** が必要なら、MSIX の意味が大きい
- **独自 updater** は最後の切り札であって、最初の選択肢ではない
- **閉域** では、賢さより単純さが勝つことが多い

もし迷っているなら、  
まずは **「per-user か per-machine か」「OS へ何を登録するか」「更新頻度はどのくらいか」**  
の 3 つだけでも先に固定すると、話がかなり前に進みます。

## 9. 参考資料

- Microsoft Learn, [Windows Installer - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/msi/windows-installer-portal)
- Microsoft Learn, [What is MSIX?](https://learn.microsoft.com/en-us/windows/msix/overview)
- Microsoft Learn, [Packaging overview - Windows apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/)
- Microsoft Learn, [MSIX features and supported platforms](https://learn.microsoft.com/en-us/windows/msix/supported-platforms)
- Microsoft Learn, [App Installer file overview](https://learn.microsoft.com/en-us/windows/msix/app-installer/app-installer-file-overview)
- Microsoft Learn, [Prepare to package a desktop application (MSIX)](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-prepare)
- Microsoft Learn, [Know your installer](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/know-your-installer)
- Microsoft Learn, [Convert an installer that includes services](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/convert-an-installer-with-services)
- Microsoft Learn, [ClickOnce Deployment and Security](https://learn.microsoft.com/en-us/visualstudio/deployment/clickonce-security-and-deployment?view=visualstudio)
- Microsoft Learn, [Manage Updates for a ClickOnce Application](https://learn.microsoft.com/en-us/visualstudio/deployment/how-to-manage-updates-for-a-clickonce-application?view=visualstudio)
- Microsoft Learn, [Choosing a ClickOnce Deployment Strategy](https://learn.microsoft.com/en-us/visualstudio/deployment/choosing-a-clickonce-deployment-strategy?view=visualstudio)
- Microsoft Learn, [ClickOnce Cache Overview](https://learn.microsoft.com/en-us/visualstudio/deployment/clickonce-cache-overview?view=visualstudio)
- Microsoft Learn, [Deploying the .NET Framework and Applications](https://learn.microsoft.com/en-us/dotnet/framework/deployment/)
- Microsoft Learn, [Windows App SDK deployment guide for self-contained apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)

[^1]: Microsoft Learn, [Windows Installer - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/msi/windows-installer-portal)
[^2]: Microsoft Learn, [Packaging overview - Windows apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/)
[^3]: Microsoft Learn, [What is MSIX?](https://learn.microsoft.com/en-us/windows/msix/overview)
[^4]: Microsoft Learn, [ClickOnce Deployment and Security](https://learn.microsoft.com/en-us/visualstudio/deployment/clickonce-security-and-deployment?view=visualstudio)
[^5]: Microsoft Learn, [Deploying the .NET Framework and Applications](https://learn.microsoft.com/en-us/dotnet/framework/deployment/)
[^6]: Microsoft Learn, [Manage Updates for a ClickOnce Application](https://learn.microsoft.com/en-us/visualstudio/deployment/how-to-manage-updates-for-a-clickonce-application?view=visualstudio)
[^7]: Microsoft Learn, [App Installer file overview](https://learn.microsoft.com/en-us/windows/msix/app-installer/app-installer-file-overview)
[^8]: Microsoft Learn, [Prepare to package a desktop application (MSIX)](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-prepare)
[^9]: Microsoft Learn, [Convert an installer that includes services](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/convert-an-installer-with-services) / [MSIX features and supported platforms](https://learn.microsoft.com/en-us/windows/msix/supported-platforms) / [Know your installer](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/know-your-installer)
[^10]: Microsoft Learn, [Know your installer](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/know-your-installer)
[^11]: Microsoft Learn, [MSIX features and supported platforms](https://learn.microsoft.com/en-us/windows/msix/supported-platforms)
[^12]: Microsoft Learn, [Packaging overview - Windows apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/)
[^13]: Microsoft Learn, [Choosing a ClickOnce Deployment Strategy](https://learn.microsoft.com/en-us/visualstudio/deployment/choosing-a-clickonce-deployment-strategy?view=visualstudio)
[^14]: Microsoft Learn, [ClickOnce Cache Overview](https://learn.microsoft.com/en-us/visualstudio/deployment/clickonce-cache-overview?view=visualstudio)
[^15]: Microsoft Learn, [Windows App SDK deployment guide for self-contained apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
