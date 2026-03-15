---
title: "Windowsアプリ開発における最低限のセキュリティを守るためのチェックリスト"
date: 2026-03-14 15:00
lang: ja
translation_key: windows-app-security-minimum-checklist
tags:
  - Windows開発
  - セキュリティ
  - 設計
  - C# / .NET
  - Win32
description: "WPF / WinForms / WinUI / C++ / C# の Windows アプリ開発で、最低限外したくないセキュリティ項目をチェックリスト形式で整理します。"
consultation_services:
  - id: windows-app-development
    reason: "権限設計、配布方式、更新方式、ログ設計まで含めて Windows アプリ全体を見直す話なので、Windowsアプリ開発 と相性がよいテーマです。"
  - id: technical-consulting
    reason: "既存アプリのセキュリティ見直しや権限境界の整理、アップデータ方針の再設計から入りたい場合は、技術相談・設計レビューとして整理できます。"
---

[Excel 版チェックリストをダウンロード](/assets/downloads/2026-03-14-windows-app-security-minimum-checklist.xlsx)

Windows アプリのセキュリティというと、話が急に大きくなりやすいです。  
ゼロトラスト、EDR、SBOM、証明書運用、脆弱性管理。どれも大事ですが、実務ではその前に外したくない最低限がかなりあります。

特に、次のようなアプリでは「高度な防御」より先に、基本の漏れを塞ぐほうが効きます。

- WPF / WinForms / WinUI のデスクトップアプリ
- C++ / C# の Win32 アプリ
- 装置連携、ファイル連携、DB 接続、社内配布ツール
- 自動更新機構を持つ業務アプリ
- Windows サービスや補助 EXE を含む構成

Windows アプリ開発では、全部を一気に完璧にするより、まず明らかに危ない穴を残さないほうが現実的です。  
ここでは、設計、実装、配布、運用の順に、最低限外したくないポイントをチェックしやすい形で整理します。

## 1. まず結論

- 最初に外したくないのは、**不要な管理者権限を要求しないこと、署名すること、秘密情報を平文で持たないこと、証明書検証を無効化しないこと**です。
- Windows アプリは、**配布物そのもの**が攻撃面になります。EXE / DLL / MSI / MSIX / 自動更新モジュールまで含めて見るほうが安全です。
- `ServerCertificateValidationCallback => true`、平文の接続文字列、`LoadLibrary("foo.dll")` の雑な読み込み、文字列連結での SQL 実行は、最低限のラインでも避けたい項目です。
- 管理者権限が必要な処理が一部だけなら、**アプリ全体を昇格させるのではなく、その部分だけを別 EXE や service に分ける**ほうが安全です。
- Windows で配布するアプリは、**署名 + タイムスタンプ**を前提に考えたほうがよいです。利用者への信頼性だけでなく、改ざん検知や運用説明もしやすくなります。
- 保存時の機密情報は、用途に応じて **DPAPI / ProtectedData** や **Credential Locker** を使い分けます。少なくとも `appsettings.json` に平文で置く状態は抜けたいところです。
- ログは多ければよいわけではありません。**トークン、パスワード、接続文字列、個人情報、フルリクエスト本文**をそのまま残すと、ログ自体が事故の主役になります。

最低限のセキュリティは、特殊な機能を足すことより、**危ない既定動作や雑な実装を残さないこと**です。

## 2. この記事の対象と「最低限」の意味

### 2.1. 対象にする範囲

この記事の対象は、たとえば次のような Windows アプリです。

- WPF / WinForms / WinUI のデスクトップアプリ
- C++ / C# の Win32 アプリ
- 社内配布ツール、装置連携ツール、監視ツール
- 補助 EXE、Windows サービス、アップデータを含む構成
- EXE / MSI / MSIX で配布する業務用ソフト

ここでいう「最低限」は、**監査に通る最終形**ではなく、**これが抜けているとかなり普通に事故る**項目です。

### 2.2. 対象外

一方で、この記事の中心からは外すものもあります。

- 企業全体のゼロトラスト設計
- EDR / SIEM / DLP / MDM の全体運用
- カーネルドライバの詳細なハードニング
- 暗号設計そのものを一から行う話
- 高度な脅威分析やフォレンジック手順

つまり、「組織全体の巨大なセキュリティ施策」ではなく、**Windows アプリ開発者がリリース前に自力で外しにくい基本線**を扱います。

## 3. まず見るチェックリスト

細かい議論の前に、まず全体を見渡せる表を置きます。  
ここだけでも、見直す場所の当たりは付きます。

### 3.1. 全体像

| 確認する項目 | 最低限やること | 典型的な NG |
| --- | --- | --- |
| 実行権限 | `asInvoker` を基本にし、昇格が必要な処理だけ分離する | アプリ全体を `requireAdministrator` にする |
| 配布物の信頼性 | EXE / DLL / MSI / MSIX にコード署名し、タイムスタンプも付ける | 未署名のまま配布する |
| 更新 | 更新元を固定し、HTTPS と署名確認で改ざん検知する | HTTP ダウンロード後にそのまま上書きする |
| 機密情報 | ソースコードや平文設定に秘密を置かず、DPAPI / Credential Locker 等を使う | API キーや接続文字列を設定ファイルに平文で置く |
| 通信 | HTTPS を使い、証明書検証を無効化しない | `return true` で証明書検証を常時スキップする |
| 外部入力 | SQL、ファイル、IPC、URI、CSV、JSON などを全部検証する | 「社内ツールだから」で素通しする |
| DLL 読み込み | 絶対パス、`SetDefaultDllDirectories`、安全な検索順序を使う | `LoadLibrary("foo.dll")` を現在ディレクトリ任せにする |
| ログ | トークン、パスワード、PII をマスクし、利用者向けエラーは出し分ける | 例外詳細や接続文字列をそのまま表示、保存する |
| 依存関係 | SDK、NuGet、VC++ ランタイム、OSS 依存を継続的に更新する | 数年単位で固定し、脆弱性情報も追わない |

### 3.2. 権限は `asInvoker` を基本にする

Windows アプリで最初に見直したいのはここです。  
アプリ全体を管理者権限で動かすと、バグや DLL すり替え、設定ファイル誤読、外部入力の不備が、そのまま強い権限で実行されます。

基本方針は次の形です。

- 通常の UI アプリは `asInvoker`
- 管理者権限が必要な処理だけ別プロセスや service に分離する
- 昇格は必要な瞬間だけ行う
- 補助 EXE や service に渡す入力も検証する

たとえば、通常は閲覧と編集だけのデスクトップアプリで、インストールやファイアウォール設定変更だけが管理者権限を必要とするなら、アプリ全体を `requireAdministrator` にするより、**昇格が必要な部分だけ broker に寄せる**ほうが安全です。

```xml
<trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
  <security>
    <requestedPrivileges>
      <requestedExecutionLevel level="asInvoker" uiAccess="false" />
    </requestedPrivileges>
  </security>
</trustInfo>
```

「管理者で動けば楽」は、だいたい後で効いてきます。  
最小権限で動かして、それでも必要な操作だけ切り出したほうが、事故の半径はかなり小さくなります。

### 3.3. バイナリとインストーラに署名する

Windows では、**配布物の信頼性**がかなり重要です。  
ユーザーが触るのはソースコードではなく、EXE、DLL、MSI、MSIX、アップデータです。ここが未署名だと、運用上の説明も、改ざん検知も、配布時の安心感も弱くなります。

最低限として見たいのは次です。

- EXE / DLL / MSI / MSIX を署名する
- インストーラだけでなく、更新に使う補助バイナリも署名する
- タイムスタンプを付ける
- 証明書の期限と更新手順を release 手順に含める

特にタイムスタンプを付けていない署名は、証明書期限切れ後の検証で困りやすいです。  
「署名してあるから終わり」ではなく、**署名 + タイムスタンプ**までを release 手順に入れておくほうが安定します。

MSIX を使うなら、パッケージ署名は前提です。  
MSI / EXE 配布でも、少なくともインストーラ本体と主要な実行バイナリは署名しておいたほうがよいです。

### 3.4. 更新経路を固定し、改ざん検知を入れる

今どきの Windows アプリでは、初回インストールより**更新経路**のほうが長く使われます。  
ここが雑だと、せっかく本体を丁寧に作っても、アップデータが一番弱いところになります。

最低限の考え方は次です。

- 更新ファイルの取得は HTTPS 前提
- ダウンロードした更新物の**署名やハッシュ**を検証する
- 更新元 URL をコードや設定で無制限に差し替えられないようにする
- 更新モジュール自身も署名する
- ロールバックや失敗時の復旧手順を決める

MSIX + App Installer を採れるなら、更新の仕組みを OS 寄りに寄せやすいです。  
一方で独自アップデータを持つなら、**通信の安全性**と**配布物の真正性**の両方を確認する必要があります。HTTPS だけでは「通信経路」は守れても、「そのファイルが本当に自分の発行物か」までは保証しません。

### 3.5. 秘密情報をソースコードや平文設定に置かない

ここは実務だと本当に事故りやすいところです。  
「社内ツールだから」「どうせ exe を配るだけだから」で、接続文字列、API キー、共有フォルダ資格情報、固定トークンをソースコードや設定ファイルに置きがちです。

最低限として避けたいものは次です。

- ソースコードに直書きした API キー
- `appsettings.json` や `app.config` の平文パスワード
- リポジトリに入った接続文字列
- 復号キーと暗号文を同じ場所に置く設計
- 利用者ごとではなく全員共通の固定資格情報

Windows アプリでの実務的な選択肢は、だいたい次です。

- **Windows の資格情報を保存したい**  
  packaged desktop app / WinUI 系なら Credential Locker を検討する
- **ローカルに秘密を暗号化保存したい**  
  Win32 / .NET なら DPAPI / `ProtectedData` を使う
- **接続先が Windows 認証や統合認証を使える**  
  可能ならアプリにパスワードを持たせない
- **クラウドやサーバー側で秘密管理できる**  
  クライアントに長期秘密を埋め込まない設計を優先する

C# なら、少なくとも次のように DPAPI を使うだけでも、平文保存よりはかなりましです。

```csharp
using System.Security.Cryptography;
using System.Text;

byte[] plaintext = Encoding.UTF8.GetBytes(secretText);
byte[] ciphertext = ProtectedData.Protect(
    plaintext,
    optionalEntropy: null,
    scope: DataProtectionScope.CurrentUser);
```

ここで大事なのは、「暗号化したから安全」ではなく、**誰が復号できるか**を設計で決めることです。  
`CurrentUser` にするのか、`LocalMachine` にするのかで意味がかなり変わります。

SQL Server 接続なら、オンプレミス環境では Windows 認証を第一候補にできることがあります。  
どうしても接続文字列に資格情報を含めるなら、少なくとも `Persist Security Info=False` を維持し、平文設定ファイルへ置きっぱなしにしないほうが安全です。

### 3.6. 通信は HTTPS 前提、証明書検証を殺さない

開発中だけのつもりで入れた抜け道が、そのまま本番に残る。  
通信まわりでは、これがかなり定番です。

特に注意したいのは次です。

- `ServicePointManager.ServerCertificateValidationCallback += ... => true`
- `HttpClientHandler.DangerousAcceptAnyServerCertificateValidator`
- 証明書失効確認を無効化したまま出荷
- 開発用の自己署名証明書前提のコードを本番に残す

最低限の方針は単純です。

- 本番通信は HTTPS
- 証明書検証を常時スキップしない
- 例外的な検証緩和が必要なら、**対象ホストと証明書を限定**する
- 開発用の回避コードはビルド条件や設定で確実に排除する
- .NET なら失効確認も意識する

ダメな例は、だいたいこうです。

```csharp
ServicePointManager.ServerCertificateValidationCallback +=
    (_, _, _, _) => true;
```

一見楽ですが、これは「この HTTPS 通信は誰に繋いでも通す」に近い動きになります。  
証明書検証を外すと、HTTPS を使っていても中身はかなり骨抜きです。

### 3.7. 外部入力を全部「信用しない入力」として扱う

Windows アプリは Web アプリではないので、入力 validation が甘くなりやすいです。  
でも実際には、外部入力の入口がかなり多いです。

- ファイルパス
- CSV / Excel / JSON / XML
- コマンドライン引数
- named pipe / socket / COM / RPC / gRPC
- DB に渡す文字列
- レジストリ値
- クリップボード
- URL / deep link
- 外部装置や SDK から返るデータ

特に最低限外したくないのは次の 3 つです。

1. **SQL は必ずパラメータ化する**  
   文字列連結で SQL を組まない。
2. **ファイルパスは正規化してから使う**  
   ユーザー指定パスをそのまま削除、上書き、展開に使わない。
3. **外部ファイルの読み込みはサイズ上限と形式チェックを入れる**  
   「開けたから安全」ではない。

SQL の例で言えば、これは避けたいです。

```csharp
var sql = "SELECT * FROM Users WHERE Name = '" + userName + "'";
```

最低限でも、こう寄せたいです。

```csharp
using System.Data;
using Microsoft.Data.SqlClient;

using var cmd = connection.CreateCommand();
cmd.CommandText = "SELECT * FROM Users WHERE Name = @name";
cmd.Parameters.Add("@name", SqlDbType.NVarChar, 256).Value = userName;
```

「社内ツールだから入力は信頼できる」は、かなり危ない前提です。  
現実には、壊れた CSV、想定外のファイル名、古い DB データ、運用者の手入力ミス、他ツールが書いた中途半端な JSON が普通に入ってきます。

### 3.8. DLL の読み込み元を曖昧にしない

これは Windows らしい落とし穴です。  
`LoadLibrary("foo.dll")` のように名前だけで DLL を読ませると、検索順序次第で意図しない場所の DLL を拾うことがあります。

最低限の方針は次です。

- 可能なら DLL の**絶対パス**を指定する
- `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)` を早い段階で設定する
- `AddDllDirectory` で明示的に検索対象を足す
- `SearchPath` の結果をそのまま `LoadLibrary` に渡す設計を避ける
- safe DLL search mode に頼り切らない

たとえば native code なら、プロセス初期化の早い段階で次を入れる設計は有力です。

```cpp
SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
```

そして、必要な追加ディレクトリだけを `AddDllDirectory` で登録します。

ここは「普段は動く」ので放置されやすいのですが、配布先で作業ディレクトリが変わったり、他製品の DLL が PATH に入っていたりすると、静かに壊れます。  
セキュリティだけでなく、障害予防としてもかなり効きます。

### 3.9. ログと例外に機密を出さない

障害調査のためにログを増やすのは大事です。  
ただし、ログは機密の墓場にもなりやすいです。

最低限として見直したいのは次です。

- パスワード、Bearer token、API キーをログに出さない
- 接続文字列を丸ごと出さない
- 個人情報や業務データ本文はマスクする
- 例外詳細は利用者向け画面と内部ログで分ける
- debug 用の PII ログを本番で有効にしない
- dump や trace の保存先権限を見直す

最近の .NET では redaction を前提にした整理もしやすくなっています。  
少なくとも、「何でも文字列化してそのまま log」はやめたいです。

よくある失敗は次です。

- HTTP request / response body を丸ごと保存する
- 認証失敗時にトークンやヘッダー全体を出力する
- 例外メッセージをそのまま MessageBox に出す
- 保守用 ZIP に機密ログを全部同梱する

エラー表示は、たとえば次のように分けます。

- **利用者向け**: 「サーバーへの接続に失敗しました。ネットワーク設定と URL を確認してください。」
- **内部ログ**: 失敗先ホスト、TLS エラー種別、相関 ID、stack trace、再試行回数

この分離だけでも、情報漏えいと調査性のバランスがかなり良くなります。

### 3.10. 依存ライブラリと開発ツールを放置しない

最後は地味ですが、かなり効く項目です。  
アプリ本体を丁寧に作っても、古いランタイムや既知脆弱性のある依存ライブラリを積んだままだと、足元が抜けます。

最低限として見たいのは次です。

- .NET SDK / runtime をサポート内の版に保つ
- NuGet / OSS 依存の更新を定期的に確認する
- C++ ならランタイム再配布物や外部 DLL の版管理をする
- 脆弱性情報の確認を release 前チェックに入れる
- 依存更新で壊れないように smoke test を用意する

ここは「後でまとめてやる」が一番危ないです。  
半年、1年と放置すると、更新差分が大きくなりすぎて、セキュリティ対応そのものが重作業になります。

## 4. リリース前チェックリスト

レビューや出荷判定の雛形として、そのまま使える形にします。  
Yes / No で確認できるよう、リリース前に最低限見たい項目を並べます。

### 4.1. 権限、実行方式

- [ ] 通常起動は `asInvoker` で動く
- [ ] 管理者権限が必要な処理は別 EXE / service などに分離している
- [ ] service を使う場合、必要以上に強い実行アカウントにしていない
- [ ] `%ProgramFiles%` 配下とユーザーデータ配下の責務を分けている

### 4.2. 配布、署名

- [ ] EXE / DLL / MSI / MSIX / updater に署名している
- [ ] 署名にタイムスタンプを付けている
- [ ] 証明書の期限と更新手順を release フローに含めている
- [ ] 配布物のハッシュ確認や改ざん検知方法が決まっている

### 4.3. 更新

- [ ] 更新取得は HTTPS で行う
- [ ] ダウンロード後に署名またはハッシュを検証する
- [ ] 更新元 URL を勝手に差し替えにくい設計になっている
- [ ] 更新失敗時のロールバックまたは再試行方針がある

### 4.4. 秘密情報

- [ ] パスワード、API キー、接続文字列をソースコードへ直書きしていない
- [ ] 平文設定ファイルに秘密を置いていない
- [ ] ローカル保存が必要な秘密は DPAPI / Credential Locker などで保護している
- [ ] 可能なところは Windows 認証やユーザー資格情報に寄せている

### 4.5. 通信

- [ ] 本番通信は HTTPS を使う
- [ ] `DangerousAcceptAnyServerCertificateValidator` や `=> true` を出荷物に残していない
- [ ] 失効確認やホスト名検証を意識している
- [ ] 開発用証明書前提のコードや設定が本番に混ざっていない

### 4.6. 入力、データアクセス

- [ ] SQL はパラメータ化している
- [ ] コマンドライン、ファイル、IPC、URI などの入力に上限と形式チェックがある
- [ ] パス操作は正規化してルート逸脱を防いでいる
- [ ] 例外メッセージをそのまま画面へ出していない

### 4.7. DLL と実行環境

- [ ] DLL の読み込み元を明示している
- [ ] `SetDefaultDllDirectories` / `AddDllDirectory` などで検索順序を制御している
- [ ] カレントディレクトリや PATH 任せの DLL 読み込みをしていない
- [ ] 配布先で動的ロードに必要なファイル群を把握している

### 4.8. ログ、運用

- [ ] トークン、パスワード、PII をログに出していない
- [ ] 内部ログと利用者向けメッセージを分けている
- [ ] dump / trace / log の保存先権限を見直している
- [ ] SDK と依存ライブラリの更新状況を確認している

## 5. よくある NG

実務でよく見るのは、だいたい次です。

### 5.1. 「社内ツールだから大丈夫」

社内ツールでも、壊れたファイル、誤操作、持ち込み端末、共有フォルダ、古い DLL、雑な権限設定は普通にあります。  
インターネット公開していなくても、攻撃面は消えません。

### 5.2. 「HTTPS だから安全」

HTTPS は大事ですが、証明書検証を無効化するとかなり意味が薄れます。  
また、更新配布では HTTPS だけでなく、**配布物の真正性確認**も必要です。

### 5.3. 「暗号化したから安全」

復号キーの置き場、復号権限、ユーザー境界、マシン境界が整理されていないと、暗号化だけでは足りません。  
特に `LocalMachine` で保護した値を「ユーザーごとの秘密」と思って使うと、後で混乱します。

### 5.4. 「ログを増やせば調査できる」

ログが多いだけで、トークンや個人情報が垂れ流しだと、それ自体がインシデントになります。  
調査性が欲しいなら、**何を残して何を伏せるか**を決めるほうが先です。

### 5.5. 「管理者で動かせば解決」

最初は楽ですが、あとで UAC、配布、サポート、権限境界、DLL 読み込み、ファイル保存先でだいたい苦しくなります。  
最小権限のほうが長期では安定します。

## 6. ざっくり優先順位

全部一気にやるのが重いなら、順番はだいたい次です。

1. **管理者権限の見直し**  
   まず `requireAdministrator` の常用をやめる。
2. **署名とタイムスタンプ**  
   配布物の信頼性を整える。
3. **秘密情報の退避**  
   ソースコード、平文設定から秘密を外す。
4. **HTTPS + 証明書検証の是正**  
   `=> true` 系を出荷物から消す。
5. **SQL / ファイル / IPC 入力の見直し**  
   文字列連結や無検証入力を減らす。
6. **DLL 読み込みの固定**  
   名前だけロード、PATH 任せをやめる。
7. **ログのマスキング**  
   事故時にログが二次災害にならないようにする。
8. **依存更新の定常化**  
   リリースのたびに確認する流れにする。

この順番なら、「まず明らかに危ない穴を塞ぐ」という意味で進めやすいです。

## 7. まとめ

Windows アプリ開発のセキュリティは、特別な製品や巨大な仕組みを入れる前に、  
**権限、署名、秘密情報、通信、入力、DLL、ログ**の 7 点を整えるだけでもかなり変わります。

最低限として押さえたいのは、次です。

- アプリ全体を管理者権限で動かさない
- 配布物と更新物に署名し、タイムスタンプを付ける
- 秘密情報をソースコードや平文設定に置かない
- HTTPS を使っても証明書検証を殺さない
- SQL、ファイル、IPC などの外部入力を信用しない
- DLL の読み込み元を曖昧にしない
- ログに機密を出さない
- 依存ライブラリを放置しない

セキュリティの話は広いですが、最初から全部をやる必要はありません。  
ただ、**危ない既定動作をそのまま出荷しない**という最低限だけは、かなり早い段階で揃える価値があります。

## 8. 参考資料

- [Administrator Broker Model - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/secauthz/administrator-broker-model)
- [How User Account Control works](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works)
- [Authenticode Digital Signatures](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/authenticode)
- [Time Stamping Authenticode Signatures](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures)
- [Sign a Windows app package](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)
- [Credential Locker for Windows apps](https://learn.microsoft.com/en-us/windows/apps/develop/security/credential-locker)
- [CryptProtectData function (dpapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)
- [CA5359: Do not disable certificate validation](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca5359)
- [CA5399: Enable HttpClient certificate revocation list check](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca5399)
- [Configuring parameters - ADO.NET Provider for SQL Server](https://learn.microsoft.com/en-us/sql/connect/ado-net/configure-parameters?view=sql-server-ver17)
- [Connection String Syntax - ADO.NET](https://learn.microsoft.com/en-us/dotnet/framework/data/adonet/connection-string-syntax)
- [Dynamic-Link Library Security - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-security)
- [SetDefaultDllDirectories function (libloaderapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-setdefaultdlldirectories)
- [Data redaction in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/data-redaction)
