---
title: "Windows の管理者特権が必要になるのはいつなのか - UAC、保護領域、設計上の見分け方"
date: 2026-03-23 10:00
lang: ja
translation_key: windows-admin-privilege-when-required
tags:
  - Windows
  - UAC
  - セキュリティ
  - 配布
  - Windows開発
description: "Windows で管理者特権が必要になる場面を、UAC、保護領域、サービス、ドライバ、per-user/per-machine 設計の観点から実務向けに整理します。"
consultation_services:
  - id: windows-app-development
    reason: "管理者権限が必要な処理を設計上どこで分離するかは、Windows アプリの運用性と保守性を大きく左右するため、Windowsアプリ開発と相性がよいテーマです。"
  - id: technical-consulting
    reason: "UAC、per-user/per-machine 配布、保護領域アクセスの境界をどこで切るかは実装前の設計判断が重要で、技術相談・設計レビューとして整理する価値があります。"
---

Windows まわりの相談で、かなりよく混ざる話があります。

- どんな時に「管理者として実行」が必要になるのか
- 管理者アカウントなのに、なぜまだ UAC が出るのか
- インストールは必ず管理者なのか
- `Program Files` に置きたいが、実行時まで昇格が必要になるのか
- `HKCU` と `HKLM` の違いは、実務では何に効いてくるのか
- 「一部の処理だけ」管理者特権が必要なアプリはどう作るべきか

この話は、単に「その人が管理者かどうか」だけでは決まりません。  
実際には、**どこへ書くのか、誰に影響する変更なのか、OS のどの保護対象に触るのか** で、かなり決まります。

この記事では、Windows で管理者特権が必要になる場面を、UAC の前提から順に整理しつつ、**どこまでが標準ユーザー権限で済み、どこからが昇格の話になるのか** を実務向けにまとめます。  
内容は **2026 年 3 月時点** で確認できる Microsoft の公式情報を前提にしています。[^uac-overview][^uac-how][^uac-architecture][^uac-design][^admin-protection]

## 1. まず結論

先に結論だけ並べると、実務ではだいたい次です。

- Windows で管理者特権が必要かどうかは、**「すごい処理かどうか」よりも、「OS やマシン全体に影響するかどうか」** で決まります。[^uac-overview][^uac-design]
- **自分のプロファイルだけ** に閉じた処理、たとえば `%AppData%`、`%LocalAppData%`、`HKCU`、`Documents` などを使う処理は、通常は管理者特権なしで済みます。[^game-uac][^registry-virt]
- 逆に、**マシン全体・全ユーザー・保護領域** に触る処理、たとえば `Program Files`、`Windows`、`System32`、`HKLM`、`HKCR` の machine-wide な設定、Windows サービス、カーネルドライバ、ファイアウォール、最高権限タスクなどは、管理者特権が必要になりやすいです。[^uac-design][^game-uac][^service-rights][^firewall-config][^task-runlevel]
- ここで大事なのは、**利用者が Administrators グループに所属していること** と、**そのアプリが今、管理者アクセス トークンで動いていること** は別だという点です。UAC が有効なら、管理者ユーザーでも通常プロセスは標準ユーザー相当で動き、必要なときだけ昇格します。[^uac-how][^game-uac]
- **インストール = 必ず管理者** ではありません。per-user インストールのように、`%LocalAppData%` 配下へ入れる前提なら、管理者特権なしで配布・更新できる設計もあります。[^per-user-rdc][^per-machine-onedrive]
- 「なぜか毎回管理者権限が必要なアプリ」は、実際には **実行時データを保護領域へ書いている** か、**マニフェストで `requireAdministrator` / `highestAvailable` を宣言している** ことが多いです。[^uac-design][^app-manifests]
- これからの方向性としても、Windows は **必要な瞬間だけ明示的に昇格する** 方向に寄っています。Windows 11 の Administrator protection（preview）は、その流れをかなりはっきり示しています。[^admin-protection]

要するに、**「管理者特権が必要か」は、利用者の肩書きではなく、アプリが触る境界で決まる** と見ておくのが一番実務的です。

## 2. そもそも「管理者特権が必要」とは何か

この話で最初に整理したいのは、**ユーザー** と **プロセス** を分けて考えることです。

Windows の UAC は、OS への不正な変更を防ぐためのセキュリティ機能です。Microsoft Learn でも、**管理者レベルのアクセス許可が必要な変更を行うとき、UAC が通知する** と説明されています。[^uac-overview]

さらに、UAC の公式説明では、**管理者アクセス トークンを必要とするアプリは、エンドユーザーに同意を求める** とされており、**子プロセスは親プロセスのアクセス トークンを継承し、親子は同じ整合性レベルで動く** とされています。[^uac-how]

ここから分かることは 2 つあります。

### 2.1 「管理者ユーザー」でも、普段はずっと管理者として動いているわけではない

Microsoft Learn では、UAC 有効時には **Administrators グループのメンバーが起動したプロセスも、特に昇格しない限り標準ユーザー権限で実行される** と説明されています。[^game-uac]

つまり、

- 自分の Windows アカウントは管理者
- でも、今ダブルクリックして起動したアプリは非昇格
- だから、管理者特権が必要な操作の瞬間だけ UAC が出る

というのは普通です。

「自分は管理者なのに、なぜまだ権限が足りないのか」は、Windows ではかなり自然な挙動です。

### 2.2 同じプロセスの中で「この処理だけ急に管理者」はできない

UAC は関数単位の魔法ではなく、**プロセスがどのトークンで動いているか** の話です。  
親子プロセスはトークンを継承するので、**非昇格の UI プロセスの中で、あるボタンを押した瞬間だけ同じプロセス内の一部メソッドを管理者化する**、という設計はできません。[^uac-how]

必要なら、

- 別 EXE に切り出す
- サービスを使う
- 最高権限タスクを使う
- 昇格 COM を使う

といった **別の実行単位** を使う必要があります。[^elevation-models]

この前提を知らないまま設計すると、だいたい「このボタンだけ管理者で実行したいのですが」という、少しつらい相談になります。

## 3. 何で決まるのか - まずは見分け方

一番分かりやすい見分け方は、次の 3 つです。

1. **どこへ書くのか**
2. **誰に影響する変更なのか**
3. **OS の保護対象に触るのか**

ざっくり判断表にすると、こんな感じです。

| やりたいこと | 典型的な対象 | 管理者特権 |
| --- | --- | --- |
| 自分用の設定・キャッシュ・ログ保存 | `%AppData%`, `%LocalAppData%`, `HKCU` | 原則不要 |
| アプリの per-user インストール / 更新 | `%LocalAppData%` など | 不要で済むことがある |
| 全ユーザー向けインストール / 更新 | `Program Files`, `HKLM` | たいてい必要 |
| 実行時に保護領域へ書き込む | `Program Files`, `Windows`, `System32`, `HKLM`, `HKCR` | 必要になる設計 |
| Windows サービスの登録 / 構成変更 | SCM, service config | 必要 |
| カーネルドライバの導入 | driver / kernel | 必要 |
| Windows Firewall ルールの変更 | firewall policy | 管理者が必要 |
| タスクを `HIGHEST` で実行する | Task Scheduler | 昇格前提 |

つまり、かなり乱暴にまとめるとこうです。

- **自分のための変更** なら、標準ユーザーで済みやすい
- **全員のための変更** なら、管理者が絡みやすい
- **OS の安全側の境界** に触るなら、管理者が必要

この 3 つを先に見るだけで、「なぜ UAC が出るのか」はだいぶ説明しやすくなります。

## 4. 管理者特権が必要になりやすい典型例

### 4.1 全ユーザー向けのインストール、更新、アンインストール

Microsoft Learn の UAC アーキテクチャの説明では、**多くのインストーラーはシステム ディレクトリやレジストリ キーへ書く** ため、標準ユーザーには十分なアクセス権がなく、Windows はインストール プログラムを検出して昇格を求めるとされています。[^uac-architecture]

ここでポイントなのは、**インストーラーが「インストーラーだから偉い」のではなく、書き込み先が保護領域だから昇格が必要** だということです。

たとえば次のようなケースです。

- `Program Files` へ配置する
- `HKLM` に machine-wide な情報を書く
- 全ユーザー向けの COM 登録や統合を行う
- サービスやドライバを入れる
- マシン全体の更新経路を持つ

このあたりは、管理者特権が必要になりやすいです。[^uac-architecture][^service-rights]

### 4.2 実行時データを `Program Files` や `HKLM` に書く

これもかなり多いです。  
Microsoft の UAC 設計ガイドでは、**不要な昇格をなくすべきであり、多くの古いソフトは HKLM / HKCR や Program Files / Windows System folders に書くために、不要に管理者特権を必要としている** と説明されています。[^uac-design]

さらに、標準ユーザーについての説明では、**`Program Files` フォルダーや `HKEY_LOCAL_MACHINE` へは書けず、システムを変更するような処理もできない** と明記されています。[^game-uac]

つまり、

- 設定ファイル
- ログ
- キャッシュ
- ユーザーごとの状態
- 最近使った履歴

のような **実行時に変わるデータ** を、インストール先フォルダーや `HKLM` に置いていると、それだけで「このアプリは管理者で起動しないと動かない」になりやすいです。

そしてこれは、アプリが本当に管理者向けだからではなく、**保存場所の選び方が悪い** だけで起きることがかなりあります。

### 4.3 Windows サービスの登録や構成変更

サービスは OS の管理対象なので、当然ながら軽くは触れません。

サービス制御マネージャーのアクセス権の公式ドキュメントでは、**`CreateService` を呼ぶには `SC_MANAGER_CREATE_SERVICE` が必要** であり、**`CreateService` に使えるハンドルを開けるのは Administrator privileges を持つプロセスだけ** と説明されています。[^service-rights]

また、**`ChangeServiceConfig` / `ChangeServiceConfig2` に必要な `SERVICE_CHANGE_CONFIG` は、システムが実行する EXE を変更できてしまうため、管理者のみに付与すべき** とされています。[^service-rights]

なので、

- サービスを登録する
- サービスの実行ファイルや起動種別を変える
- サービスを削除する
- サービスのセキュリティ記述子を変える

のような処理は、管理者特権が必要になりやすいです。

### 4.4 カーネルドライバを入れる

Microsoft Learn では、標準ユーザーは **kernel-mode driver のインストールのような、システムを変更するタスクを実行できない** と説明されています。[^game-uac]

これはかなり分かりやすい境界です。  
ドライバはカーネル側で動くので、普通の「ユーザーアプリの設定保存」と同列には扱えません。

- デバイスドライバを導入する
- 仮想ドライバやフィルタドライバを入れる
- ブートや I/O に関わる部品を変える

こうした処理は、管理者特権が必要になると考えてよいです。

### 4.5 ファイアウォールや高権限タスクの設定

ファイアウォールも OS のセキュリティ境界の一部です。  
Microsoft Learn のファイアウォール設定手順では、**単一デバイスで Windows Firewall with Advanced Security を操作するには、そのデバイス上の administrative rights が必要** と明記されています。[^firewall-config]

また、タスク スケジューラについては、**`TASK_RUNLEVEL_LUA` は最小権限、`TASK_RUNLEVEL_HIGHEST` は最高権限で実行** と定義されており、`schtasks` のドキュメントでも **ローカル コンピューター上のすべてのタスクを schedule / view / change するには Administrators グループのメンバーである必要がある** とされています。[^task-runlevel]

つまり、

- Windows Firewall ルールを追加・変更する
- 特定の処理を最高権限タスクとして登録する
- 別ユーザーや SYSTEM でジョブを動かす

といった構成は、管理者特権が必要になる側にあります。

## 5. 実は管理者特権が不要で済むことが多い典型例

「Windows はすぐ管理者を要求する」と見えがちですが、実際には **管理者特権が不要な設計にできる部分** もかなり多いです。

### 5.1 自分用の設定、キャッシュ、ログ

Microsoft Learn では、互換性のための仮想化に頼るのではなく、**アプリは per-user location か、ACL を正しく設定した `%alluserprofile%` 内の computer location に保存するべき** と説明されています。[^registry-virt]

実務的には、次のように分けると整理しやすいです。

- **ユーザー固有**: `%AppData%`, `%LocalAppData%`, `HKCU`
- **共有だが実行時に更新される**: `%ProgramData%` + ACL 設計
- **実行ファイル本体**: `Program Files` などの保護領域

この分離ができていれば、**アプリ本体のインストールは管理者でも、普段の利用は非管理者** にできます。

### 5.2 per-user インストールと更新

Microsoft の公式ドキュメントでも、per-user 配置の例は普通に出てきます。

たとえば Remote Desktop client のドキュメントでは、**per-user インストールは各ユーザープロファイルの `LocalAppData` 配下へインストールし、ユーザーが管理者権限なしで更新できる** と説明されています。[^per-user-rdc]

また OneDrive のドキュメントでは、**既定では per-user インストール** であり、**per-machine インストールは `/allusers` を付けてコマンドを実行し、その結果 UAC プロンプトが出る** とされています。さらに、per-user は `%localappdata%`、per-machine は `Program Files` 配下に入ります。[^per-machine-onedrive]

ここから分かるのは、**「インストール」という単語だけでは、管理者特権の要否は決まらない** ということです。

- 各ユーザーが自分の領域へ入れるなら、非管理者で済む場合がある
- 全ユーザー共通の領域へ入れるなら、管理者が要りやすい

大事なのは **per-user か per-machine か** を先に決めることです。

### 5.3 通常の UI 操作や業務ロジック

逆に言うと、次のような処理は、それ自体では管理者特権を必要としません。

- 文書や画像を開く
- 自分のプロファイル配下のファイルを編集する
- HTTP 通信や DB 通信を行う
- 業務ロジックを実行する
- 画面に結果を表示する
- 自分用設定を読み書きする

にもかかわらず「アプリ全体を管理者として実行」が必要になっているなら、原因はアプリの本体機能ではなく、**一部の周辺処理が保護領域へ触っている** ことが多いです。

## 6. なぜ「このアプリは管理者で」と言われるのか

### 6.1 マニフェストで `requireAdministrator` を宣言している

アプリケーション マニフェストでは、`requestedExecutionLevel` により、必要な権限レベルを宣言できます。Microsoft Learn では、次の 3 つが定義されています。[^app-manifests]

- `asInvoker`: 起動元プロセスと同じ権限で動く
- `highestAvailable`: 可能な限り高い権限で動く
- `requireAdministrator`: 管理者権限で動く

もしアプリが `requireAdministrator` になっていれば、**起動のたびに昇格が前提** になります。  
`highestAvailable` でも、環境によっては昇格が絡みます。[^app-manifests]

なので、「なぜ毎回 UAC が出るのか」の一番素直な答えは、**そのアプリがそう宣言しているから** です。

### 6.2 Windows の installer detection に引っかかっている

UAC アーキテクチャの説明では、Windows には **installer detection technology** があり、**多くのインストール プログラムは protected system locations に書くため、昇格が必要になる** と説明されています。[^uac-architecture]

しかもこれは、単純に setup.exe という名前だからではなく、Windows がある程度 **ヒューリスティックに「これはインストーラーっぽい」と判定** しています。公式ドキュメントでは、次の条件が挙げられています。[^uac-architecture]

- 32-bit 実行ファイル
- `requestedExecutionLevel` 属性がない
- UAC 有効の標準ユーザーによる対話プロセス
- ファイル名に `install`、`setup`、`update` といった語を含む、など

なので、`SetupLauncher.exe` や `Updater.exe` が突然昇格を求めるのは、Windows 側の設計として不思議ではありません。

### 6.3 旧来アプリが仮想化で「たまたま動いていた」

ここはかなり誤解されやすいです。

Microsoft Learn では、**UAC は保護領域へ書こうとする非準拠アプリのために、ファイルとレジストリの仮想化を提供する** と説明されています。  
一方でこれは **短期的な互換性対策であり、長期的な解決策ではない** とも明記されています。[^uac-architecture][^registry-virt]

さらに、仮想化には制限があります。

- **昇格済みアプリには適用されない**
- **32-bit アプリにしか適用されない**
- **`requestedExecutionLevel` を含むマニフェストがあると無効**
- **アプリは本来、正しい保存先へ書くよう修正するべき**

という条件です。[^uac-architecture][^registry-virt]

つまり、昔の 32-bit アプリが「管理者なしでも Program Files に書けていたように見える」ことがありますが、それは **正しく書けていたのではなく、VirtualStore に逃がされていた** だけかもしれません。

このため、

- 64-bit 化した
- マニフェストを追加した
- ビルド方法を変えた
- UAC 準拠を進めた

といったタイミングで、以前は表面化しなかった「保存先の設計ミス」が急に見えることがあります。

### 6.4 そもそも実行時に触る場所がよくない

実務では、結局これがいちばん多いです。

- 設定を EXE の隣へ保存する
- ログをインストール先へ吐く
- 一時ファイルを `Program Files` 配下へ作る
- ユーザーごとの状態を `HKLM` に書く

こういう構成にすると、**アプリ本体は普通の UI なのに、起動に管理者特権が必要** という、かなり扱いにくい形になります。[^uac-design][^game-uac]

「その処理が高度だから管理者」ではなく、**保存先が悪いから管理者** というケースは、本当に多いです。

## 7. どう設計すると無駄な昇格を減らせるか

### 7.1 基本は `asInvoker`

アプリ全体が本当にシステム管理ツールでない限り、基本線は **通常の UI アプリを非昇格で動かす** ことです。  
マニフェストの意味としても、`asInvoker` は「起動元と同じ権限で動く」という宣言です。[^app-manifests]

普段の画面操作、業務ロジック、ユーザーごとの設定保存まで全部管理者で動かすと、

- 攻撃面が広がる
- 運用説明がしにくい
- 毎回 UAC が出る
- 「本当はどの処理に管理者が必要なのか」が見えなくなる

という問題が増えます。Microsoft の UAC 設計ガイドも、**不要な昇格をなくし、管理者特権が必要なのは本当に必要なタスクだけにすべき** と説明しています。[^uac-design]

### 7.2 管理者が必要な処理だけ、別の実行単位へ分ける

Microsoft Learn には、**管理者特権が必要な処理を持つアプリでも、標準ユーザーアプリとして動かしつつ必要部分だけを分離するモデル** が明示されています。[^elevation-models]

代表的には次の 4 つです。

- **Administrator Broker Model**  
  標準ユーザーの UI アプリ + 管理者 helper EXE
- **Operating System Service Model**  
  標準ユーザー UI + 常駐 service
- **Elevated Task Model**  
  標準ユーザー UI + 最高権限のスケジュールタスク
- **Administrator COM Object Model**  
  標準ユーザー UI + 昇格 COM

ざっくりした使い分けはこうです。

- **たまにだけ管理者操作** が必要なら helper EXE
- **常時・無人・頻繁** なら service
- **短い定型ジョブ** なら highest task
- **既存 COM 前提** なら昇格 COM

Windows アプリでこの設計を具体化する話は、別記事の  
[Windowsアプリで「管理者権限が必要な処理だけ」を分離する具体的な書き方](https://comcomponent.com/blog/2026/03/16/001-windows-admin-broker-deep-dive/)  
でも詳しく扱っています。

### 7.3 実行時データの置き場所を正す

保存先の原則は、かなり単純です。

- **ユーザー固有のデータ** は `HKCU` や `%AppData%`
- **ローカル専用キャッシュ** は `%LocalAppData%`
- **共有だが実行時に変わるデータ** は `%ProgramData%` + ACL
- **実行ファイル本体** は `Program Files`

Microsoft Learn でも、アプリは **per-user location か、ACL を正しく設定した `%alluserprofile%`（実体は `ProgramData`）へ保存すべき** と説明されています。[^registry-virt]

この整理をすると、**インストーラーだけ昇格し、実行中アプリは非昇格** にしやすくなります。

### 7.4 per-user と per-machine を先に決める

意外と見落としやすいのがここです。

- **そのアプリは各ユーザーが自分で入れられるべきか**
- **全ユーザー共通の 1 か所に入れるべきか**
- **更新は誰が責任を持つのか**
- **実行ファイルをユーザープロファイルから動かしてよいのか**

この判断が曖昧だと、あとで

- インストールだけ管理者
- 実行も管理者
- 更新も管理者
- 一部だけ user context

のように、ぐちゃっとしやすいです。

per-user / per-machine の違いは、単に配布方式の話ではなく、**権限設計そのもの** です。

## 8. これからの Windows はどちらへ向かっているか

2026 年 3 月時点で、Windows 11 には **Administrator protection (preview)** という機能があります。Microsoft Learn では、この機能を **通常時は deprivileged state を保ち、必要なときだけ just-in-time で admin rights を与える** ものとして説明しています。[^admin-protection]

さらに Microsoft は、**ソフトウェアのインストール、時刻やレジストリのようなシステム設定の変更、機微データへのアクセス** といった管理者特権が必要な操作の前に、明示的な認証を求めると説明しています。[^admin-protection]

この機能自体はまだ preview で、一般展開も段階的です。[^admin-protection]  
ただ、方向性としてはかなり明確です。

- 常時管理者トークンを持ちっぱなしにしない
- 必要な瞬間だけ昇格する
- 昇格したセッションを分離する
- 「いつ、どのアプリが、なぜ管理者になったか」をより明確にする

つまり、**「とりあえず全部管理者で動かす」設計は、今後ますます相性が悪くなる** と見てよいです。

## 9. よくある誤解

### 9.1 「自分は管理者ユーザーだから、UAC は出ないはず」

出ます。  
UAC 有効時は、Administrators グループのメンバーでも通常プロセスは非昇格で動き、必要時だけ昇格します。[^game-uac][^uac-how]

### 9.2 「インストールなら必ず管理者」

必ずではありません。  
`%LocalAppData%` への per-user インストールのように、管理者特権なしで配れる設計はあります。[^per-user-rdc][^per-machine-onedrive]

### 9.3 「Program Files に置くのだから、設定もそこに保存してよい」

だめです。  
実行ファイルの配置先と、実行時に変わるデータの保存先は分けるべきです。Microsoft も、Program Files や `HKLM` への実行時書き込みを、不要な昇格の典型例として挙げています。[^uac-design][^registry-virt]

### 9.4 「管理者として実行さえすれば、設計問題は全部解決する」

解決しません。  
一時的に動くことはあっても、攻撃面、運用性、配布、サポートのしやすさは悪化しやすいです。しかも、同じプロセスの中の一部だけを都合よく昇格することもできません。[^uac-how][^elevation-models]

### 9.5 「昔は動いていたから、今も正しい」

そうとは限りません。  
旧来の 32-bit アプリが仮想化で「たまたま動いていた」だけなら、64-bit 化やマニフェスト追加で問題が表面化します。仮想化は互換性のための暫定策で、長期解ではありません。[^uac-architecture][^registry-virt]

## 10. まとめ

Windows の管理者特権が必要かどうかは、ひとことで言えば、**「どこへ何を変えにいくのか」** で決まります。

- **自分のための変更** なら、標準ユーザーで済みやすい
- **全ユーザー・マシン全体の変更** なら、管理者が必要になりやすい
- **OS の保護領域やセキュリティ境界** に触るなら、管理者特権が必要

そして実務で本当に大事なのは、**本当に管理者特権が必要な処理** と、**単に保存先の都合で管理者が必要になってしまっている処理** を分けることです。

特に Windows アプリ開発では、次の線がかなり有効です。

- UI は非昇格を基本にする
- 管理者処理は別 EXE / service / task に切る
- 実行時データは `AppData` / `HKCU` / `ProgramData` 側へ寄せる
- per-user / per-machine を最初に決める

「管理者特権が必要か」は、アプリが立派かどうかの話ではありません。  
**OS のどの境界に触っているか** の話です。

この見方を最初に持っておくと、UAC の挙動も、インストール方式の選定も、アプリ設計も、かなり整理しやすくなります。

## 11. 関連記事

- [Windowsアプリで「管理者権限が必要な処理だけ」を分離する具体的な書き方](https://comcomponent.com/blog/2026/03/16/001-windows-admin-broker-deep-dive/)
- [Windowsアプリ開発における最低限のセキュリティを守るためのチェックリスト](https://comcomponent.com/blog/2026/03/14/001-windows-app-security-minimum-checklist/)
- [Windows アプリの配布方式をどう選ぶか - MSI / MSIX / ClickOnce / xcopy / 独自 updater の判断表](https://comcomponent.com/blog/2026/03/20/000-windows-app-deployment-msi-msix-clickonce-xcopy-custom-updater/)

## 12. 参考資料

[^uac-overview]: Microsoft Learn, [User Account Control](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/). UAC は OS への不正変更を防ぐためのセキュリティ機能で、管理者レベルのアクセス許可が必要な変更時に通知します。
[^uac-how]: Microsoft Learn, [How User Account Control works](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works). 管理者アクセス トークンを必要とするアプリは同意プロンプトの対象であり、子プロセスは親のトークンを継承します。
[^uac-architecture]: Microsoft Learn, [UAC Architecture](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/architecture). 保護領域、installer detection、仮想化、`requestedExecutionLevel` の関係について。
[^uac-design]: Microsoft Learn, [User Account Control (Design basics)](https://learn.microsoft.com/en-us/windows/win32/uxguide/winenv-uac). 不要な昇格をなくし、Program Files / Windows / HKLM / HKCR への実行時書き込みを避けるべきと説明しています。
[^game-uac]: Microsoft Learn, [User Account Control for Game Developers](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/user-account-control-for-game-developers). 標準ユーザーは `Program Files` や `HKEY_LOCAL_MACHINE` に書けず、カーネルドライバ導入のような system-changing task も行えません。
[^registry-virt]: Microsoft Learn, [Registry Virtualization](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-virtualization). 仮想化は互換性のための暫定策であり、アプリは per-user か ACL を正しく設定した `%alluserprofile%` 側へ保存すべきとされています。
[^app-manifests]: Microsoft Learn, [Application manifests](https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests). `requestedExecutionLevel` の `asInvoker` / `highestAvailable` / `requireAdministrator` について。
[^service-rights]: Microsoft Learn, [Service Security and Access Rights](https://learn.microsoft.com/en-us/windows/win32/services/service-security-and-access-rights). `CreateService` や `ChangeServiceConfig` に必要なアクセス権、および管理者権限との関係について。
[^firewall-config]: Microsoft Learn, [Configure rules with group policy](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/configure). 単一デバイスで Windows Firewall with Advanced Security を操作するには administrative rights が必要です。
[^task-runlevel]: Microsoft Learn, [Principal.RunLevel property](https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-runlevel), [TASK_RUNLEVEL_TYPE enumeration](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_runlevel_type), [schtasks change](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-change). タスクの最小権限 / 最高権限、およびタスク変更に必要な権限について。
[^per-user-rdc]: Microsoft Learn, [Install the Remote Desktop client for Windows on a per-user basis with Intune or Configuration Manager](https://learn.microsoft.com/en-us/previous-versions/remote-desktop-client/install-windows-client-per-user). per-user インストールでは各ユーザーの `LocalAppData` 配下へ入り、管理者権限なしで更新できます。
[^per-machine-onedrive]: Microsoft Learn, [Install the sync app per-machine (Windows)](https://learn.microsoft.com/en-us/sharepoint/per-machine-installation). OneDrive は既定では per-user で、`/allusers` による per-machine インストールでは UAC プロンプトが発生し、`Program Files` 配下へ入ります。
[^elevation-models]: Microsoft Learn, [Developing Applications that Require Administrator Privilege](https://learn.microsoft.com/en-us/windows/win32/secauthz/developing-applications-that-require-administrator-privilege). Elevated Task / Service / Administrator Broker / Administrator COM の分離モデルを整理しています。
[^admin-protection]: Microsoft Learn, [Administrator protection (preview)](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/administrator-protection/). Windows 11 における least privilege / just-in-time elevation の方向性について。
