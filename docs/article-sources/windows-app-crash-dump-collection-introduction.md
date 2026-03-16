---
title: "Windows アプリのクラッシュダンプ収集入門 - まず WER / ProcDump / WinDbg をどう使い分けるか"
slug: "windows-app-crash-dump-collection-introduction"
date: "2026-03-16T10:00:00+09:00"
author: "小村 豪"
description: "Windows アプリで再現しにくいクラッシュを追うときに、WER LocalDumps、ProcDump、MiniDumpWriteDump をどう使い分けるかを入門向けに整理します。ミニダンプとフルダンプの選び方、運用上の注意点、WinDbg で最初に見るポイントまでまとめます。"
tags:
  - "Windows開発"
  - "不具合調査"
  - "クラッシュダンプ"
  - "WER"
  - "ProcDump"
  - "WinDbg"
---

Windows アプリで「たまにだけ落ちる」が始まると、ログだけでは追い切れない場面がかなりあります。

特に、次のようなケースです。

- 顧客環境でしか起きない
- 例外メッセージは取れているが、呼び出し元の文脈が足りない
- C# / .NET の managed 側だけでなく、COM、P/Invoke、native DLL、vendor SDK が絡む
- 長時間運転後にだけ落ちる

こういうときに効くのがクラッシュダンプです。クラッシュ時点のプロセス状態をファイルに落としておけば、例外コード、落ちたスレッドのスタック、読み込まれていたモジュール、メモリの一部または全部を後から読めます。

Windows では、まず WER の LocalDumps、必要に応じて Sysinternals ProcDump、さらに制御したくなったら MiniDumpWriteDump を使う、という順で考えるのが分かりやすいです。この記事では、Windows デスクトップアプリ、常駐アプリ、Windows サービス、装置連携ツールなどを前提に、クラッシュダンプ収集の最初の一歩を整理します。

## 目次

1. まず結論
2. クラッシュダンプで何が分かるか
3. 収集方法の全体像
4. 最初のおすすめは WER LocalDumps
   - 4.1. まず見るレジストリ値
   - 4.2. アプリ単位で設定する例
   - 4.3. 取れたか確認する
5. ProcDump を使う場面
   - 5.1. よく使うオプション
   - 5.2. 代表的なコマンド例
   - 5.3. `-i` を最初の一手にしない理由
6. 自前収集で `MiniDumpWriteDump` を使うときの考え方
7. ミニダンプ / フルダンプ / 中間サイズの選び方
8. 運用で先に決めておくこと
9. 取れた後の最短解析導線
10. よくあるはまりどころ
11. まとめ
12. 参考資料

## 1. まず結論

最初に押さえたい点だけを先に並べます。

- まずは **WER LocalDumps をアプリ単位で設定する** のが無難です。追加ツールなしで、クラッシュ後にローカルへダンプを残せます。
- **再現率の低い現場調査や、first chance exception / hang まで見たいなら ProcDump** を使います。
- **自前収集は最後に考える** くらいでちょうどよいです。必要になってから `MiniDumpWriteDump` を検討すれば十分です。
- **ダンプと同じくらい大事なのが PDB と配布バイナリの保管** です。ダンプだけあっても、シンボルがなければ読める量がかなり減ります。
- **フルダンプは強いが、サイズと機密情報の混入リスクも強い** です。保管場所、保持数、アクセス権、共有手順を先に決めます。

入門段階のおすすめ構成は、だいたい次です。

| 環境 | まずの構成 |
| --- | --- |
| 開発機 / 検証機 | WER LocalDumps をアプリ単位で設定し、まずは `DumpType=2` のフルダンプ |
| 顧客環境 / 現場機 | 容量と機密要件を見て `DumpType=1` か `2` を選ぶ。必要時だけ ProcDump を追加 |
| 長時間運転や hang 調査 | WER に加えて ProcDump の `-h` や `-e 1` を検討 |
| 独自 UI や添付ログも含めたい | 別プロセス前提で `MiniDumpWriteDump` を使う自前収集 |

要するに、**最初は WER、次に ProcDump、最後に自前** です。ここを逆順で始めると、だいたい設計が重くなります。

## 2. クラッシュダンプで何が分かるか

クラッシュダンプは、「その瞬間のスナップショット」です。防犯カメラというより、事故現場の静止画に近いです。

そのため、次のような情報はかなり取りやすいです。

- どの例外コードで落ちたか
- どのスレッドが落ちたか
- その時点のコールスタック
- 読み込まれていたモジュール
- どの程度のメモリを含めたかに応じて、ヒープ上の状態やオブジェクトの中身

一方で、次のようなものはダンプだけでは不足しやすいです。

- そこへ至るまでの時系列
- 数時間前からの増加傾向
- 通信や装置との外部状態
- 直前の入力や業務文脈

なので実務では、**ダンプだけで完結しようとせず、ログや heartbeat と組み合わせる** のが基本です。

ざっくり言うと、見えやすさはこうなります。

| 種類 | 見えやすいもの | 弱いところ |
| --- | --- | --- |
| ミニダンプ | 例外、スタック、モジュール、基本的な状況 | ヒープやオブジェクトの中身を深く追いにくい |
| フルダンプ | プロセス全体のメモリ、ヒープ、状態再構成 | ファイルが大きい。機密情報も入りやすい |
| 中間サイズのダンプ | ミニより多く、フルより軽い | どこを残すかの調整コストがある |

## 3. 収集方法の全体像

Windows アプリのダンプ収集で、入門段階で押さえたい方法は次の 4 つです。

| 方法 | 向いている場面 | 強み | 注意点 |
| --- | --- | --- | --- |
| WER LocalDumps | まず常設したいクラッシュ収集 | Windows 標準。アプリ単位で設定しやすい | 基本はクラッシュ向け。hang や細かい条件分岐は弱い |
| ProcDump | 再現率が低い調査、hang、first chance exception | トリガーが多い。現場投入しやすい | 外部ツール運用になる |
| タスク マネージャーのダンプ作成 | 手動で今の状態を取りたい | GUI でその場で取れる | 自動収集ではない |
| `MiniDumpWriteDump` | 自前の診断機能を作りたい | 添付ログや独自メタデータを合わせやすい | 実装を雑にすると逆に壊れる |

初心者にとって一番大事なのは、**「何で取るか」より先に、「どの条件で」「どこへ」「どのサイズで」取るかを決めること** です。ここが曖昧だと、取れたダンプが読めないか、逆に大量に溜まって運用事故になります。

## 4. 最初のおすすめは WER LocalDumps

### 4.1. まず見るレジストリ値

Windows Error Reporting (WER) には、クラッシュ後にローカルへユーザーモードダンプを保存する `LocalDumps` があります。追加ツールを配らなくてよいので、まずの一手としてかなり扱いやすいです。

基本のキーは次です。

```text
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps
```

ここにグローバル設定を置くこともできますが、実務では **アプリ単位のサブキー** に寄せる方が扱いやすいです。

```text
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe
```

最初に見る値は 3 つです。

| 値 | 意味 | まずのおすすめ |
| --- | --- | --- |
| `DumpFolder` | ダンプの出力先 | 専用フォルダを切る |
| `DumpCount` | 保持数 | 5〜10 くらいから |
| `DumpType` | 0=カスタム、1=ミニ、2=フル | 最初は 2、容量が厳しければ 1 |

迷いやすいので、入門向けに言い切るとこうです。

- **原因調査を優先するなら `DumpType=2`**
- **容量や共有の軽さを優先するなら `DumpType=1`**
- **`DumpType=0` + `CustomDumpFlags` は慣れてから**

なお、`DumpFolder` を独自パスにするなら、**クラッシュしたプロセスがそのフォルダへ書ける ACL** が必要です。サービスの場合は特に、実行アカウントの権限を忘れやすいです。

### 4.2. アプリ単位で設定する例

たとえば `MyApp.exe` について、`C:\CrashDumps\MyApp` にフルダンプを最大 10 個残したいなら、まずは次のように設定できます。

```bat
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpFolder /t REG_EXPAND_SZ /d "C:\CrashDumps\MyApp" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpCount /t REG_DWORD /d 10 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpType /t REG_DWORD /d 2 /f
```

この例でのポイントは次です。

- **グローバルではなく `MyApp.exe` に限定** している
- **出力先を専用フォルダに分離** している
- **まずはフルダンプ** にしている
- **保持数を 10 に制限** している

現場配布でフルダンプが大きすぎるなら、`DumpType` だけ 1 に落とします。

```bat
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpType /t REG_DWORD /d 1 /f
```

ここでありがちな失敗は、いきなりグローバル設定を入れてしまうことです。これをやると、**自分のアプリ以外のクラッシュまで拾い始める** ので、検証機や共有サーバーが少し騒がしくなります。

### 4.3. 取れたか確認する

設定を入れたら、本番で自然発生を待つ前に **検証環境で必ず 1 回は取り切る** 方が安全です。

確認ポイントは次です。

1. 想定のフォルダに `.dmp` が出るか
2. サイズが運用想定に合うか
3. WinDbg で開けるか
4. Event Viewer の Application ログで crash が見えているか

Event Viewer 側では、`Application Error` のイベント ID 1000 や、WER 側のイベント ID 1001 が確認の手掛かりになります。ダンプが出ていなくても、ここで「そもそも crash として認識されているか」が見えます。

なお、WER LocalDumps はかなり便利ですが、**アプリが独自のクラッシュレポータを使っている場合は、そのままでは期待どおりに扱えないことがあります**。そういう構成では、最初から ProcDump か自前収集へ寄せた方が話が速いです。

## 5. ProcDump を使う場面

WER で十分なことは多いですが、次のようなときは ProcDump が便利です。

- レジストリ常設を避けたい
- 既に起動中のプロセスだけ監視したい
- 次回起動からだけ監視したい
- first chance exception を見たい
- hang を取りたい
- パフォーマンスカウンタや条件付きで採りたい

### 5.1. よく使うオプション

入門段階でよく使うものだけに絞ると、ProcDump は次を覚えておけばかなり戦えます。

| オプション | 意味 |
| --- | --- |
| `-ma` | フルダンプ |
| `-mp` | MiniPlus ダンプ |
| `-e` | 未処理例外でダンプ |
| `-e 1` | first chance / second chance 例外でダンプ |
| `-h` | ハングしたウィンドウでダンプ |
| `-w` | 対象プロセスの起動待ち |
| `-x` | 対象プロセスを起動して監視 |
| `-n` | 最大ダンプ数 |
| `-accepteula` | 初回 EULA 確認を自動承諾 |

入門向けにざっくり言うと、

- **クラッシュなら `-e`**
- **早めに拾いたい例外なら `-e 1`**
- **固まるなら `-h`**
- **まずは `-ma`**
- **数を抑えるなら `-n`**

です。

### 5.2. 代表的なコマンド例

#### 既に起動中のプロセスを、未処理例外でフルダンプ

PID が分かっているなら、まずはこれが確実です。

```bat
procdump -accepteula -ma -e 1234 C:\CrashDumps\MyApp
```

#### 次回起動を待って、未処理例外でフルダンプ

次に起動したタイミングから見たいなら `-w` が楽です。

```bat
procdump -accepteula -ma -e -w MyApp.exe C:\CrashDumps\MyApp
```

#### 自分で起動して、そのまま監視

検証機で再現試験を回すなら、`-x` が分かりやすいです。

```bat
procdump -accepteula -ma -e -x C:\CrashDumps\MyApp MyApp.exe
```

#### first chance exception も取りたい

これは便利ですが、かなり騒がしくなりやすいです。まずは件数制限を付ける方が無難です。

```bat
procdump -accepteula -ma -n 3 -e 1 MyApp.exe C:\CrashDumps\MyApp
```

#### ハングを取りたい

クラッシュではなく、画面が固まる系ならこちらです。

```bat
procdump -accepteula -h MyApp.exe C:\CrashDumps\MyApp
```

「落ちる」ではなく「止まる」問題では、こちらの方が本命だったりします。

### 5.3. `-i` を最初の一手にしない理由

ProcDump には `-i` で postmortem debugger として登録する使い方もあります。これは強力ですが、**マシン全体のクラッシュ時挙動に踏み込む** ので、入門段階の最初の一手には少し重いです。

特に、共有開発機や顧客サーバーでは次の理由で慎重に見た方がよいです。

- 調査対象以外のクラッシュ挙動にも影響する
- 解除忘れが起きやすい
- 「そのマシンで何が既定なのか」が分かりにくくなる

なので、最初は **WER のアプリ単位設定** か、**ProcDump の `-w` / `-x` / PID 指定** から入るのが扱いやすいです。

## 6. 自前収集で `MiniDumpWriteDump` を使うときの考え方

自前収集が向いているのは、たとえば次のような場面です。

- UI から「診断情報を保存」ボタンを出したい
- ダンプと一緒にログ、設定、トレース ID を束ねたい
- 関連する子プロセスや補助プロセスもまとめたい
- アップロード前に独自のマスキングや圧縮を入れたい

ここで中心になる API が `MiniDumpWriteDump` です。

ただし、ここは少し癖があります。入門で特に外したくないのは次の 2 点です。

1. **可能なら dump 対象とは別プロセスから呼ぶ**
2. **DbgHelp 系は single-threaded 前提で扱う**

クラッシュ直後の対象プロセスは、すでに不安定です。そこから同じプロセス内で無理にダンプを書こうとすると、loader deadlock やスタック枯渇など、妙な詰まり方をすることがあります。

なので、自前実装をやるとしても、最初はこういう構成に寄せる方が安全です。

1. 監視用の helper / broker プロセスを別で用意する
2. 対象 PID と出力先を helper に渡す
3. helper 側で `MiniDumpWriteDump` を呼ぶ
4. 必要ならログや設定ファイルを一緒に束ねる

要するに、**「落ちた本人が頑張って書く」より、「外から救助する」方が筋がよい** です。

## 7. ミニダンプ / フルダンプ / 中間サイズの選び方

ここで迷う人はかなり多いです。実務では次のように考えると整理しやすいです。

| 種類 | 向いている場面 | 良い点 | 注意点 |
| --- | --- | --- | --- |
| ミニダンプ | まず広く入れたい、共有を軽くしたい | 小さい、転送しやすい | 状態復元の深さは弱い |
| フルダンプ | 原因調査を優先したい、native 境界やヒープが怪しい | 取れる情報が多い | サイズが大きい、機密混入リスクが高い |
| MiniPlus / Custom | ミニでは足りず、フルは重い | バランスを取れる | 調整の知識が必要 |

初心者向けのおすすめはかなり単純です。

- **開発機 / 検証機ではフルダンプ**
- **顧客環境ではミニかフルを運用条件で選ぶ**
- **メモリ破壊、ネイティブ DLL、COM、P/Invoke、長時間稼働後の状態異常が怪しいならフル寄り**

ProcDump の `-mp` は便利そうに見えますが、**CLR プロセスではデバッグ制約によりフルダンプ相当になる** ことがあります。なので、.NET アプリで「`-mp` にすれば軽くなるはず」と思い込むと、肩透かしを食らうことがあります。

## 8. 運用で先に決めておくこと

ダンプ収集は、実装より運用で転ぶことがかなりあります。先に決めたいのは次です。

### 8.1. PDB とバイナリをどう残すか

これが最重要です。

- 配布した EXE / DLL の正確な版
- その版に対応する PDB
- どのコミット / どのビルドパイプラインで作ったか
- インストーラや配布物の版情報

ここが曖昧だと、ダンプはあるのに読み切れない、という残念な状態になります。

### 8.2. どこへ出して、何個残すか

フルダンプはかなり大きくなります。最初から次を決めておく方が安全です。

- システムドライブ直下に置きっぱなしにしない
- 専用フォルダへ分離する
- `DumpCount` や `-n` で上限を切る
- 長期保管と一次保管を分ける

### 8.3. 誰が見てよいか

フルダンプには、機密情報や個人情報が混ざる可能性があります。具体的には次です。

- 平文設定
- 接続文字列
- トークンや資格情報
- 直前に扱っていた業務データ
- ファイルパスやユーザー名

なので、**「取る」設計と同時に「誰が触れてよいか」も決める** 必要があります。

### 8.4. ログとどう合わせるか

ダンプだけだと、「この時刻に何をしていたか」が弱いことがあります。最低限、次を合わせると読みやすくなります。

- 版情報
- 起動引数
- 操作単位やジョブ単位の ID
- 直前の主要イベント
- 接続先や装置状態の要約

### 8.5. release build で確認する

開発機では Debug build で試しがちですが、実際に現場で落ちるのはたいてい Release build です。

- 最適化の有無
- inlining の有無
- 例外の見え方
- タイミングの揺れ

このへんで景色が変わるので、**収集導線は Release build でも一度確認** した方がよいです。

## 9. 取れた後の最短解析導線

ダンプを取ったあと、最初にやることは意外と素朴です。

### 9.1. WinDbg を入れる

今の WinDbg は Microsoft Store か `winget` で入れやすくなっています。

```bat
winget install Microsoft.WinDbg
```

### 9.2. ダンプを開く

GUI から開いてもよいですし、コマンドラインでも開けます。

```bat
windbg -z C:\CrashDumps\MyApp\MyApp_YYMMDD_HHMMSS.dmp
```

ここで覚えておきたいのは、**ダンプを作った Windows の版や CPU と、解析側のマシンが一致している必要はない** ことです。解析専用の別マシンで十分です。

### 9.3. シンボルを設定する

まず Microsoft 公開シンボルを使える状態にして、その後で自分の PDB の場所を足します。

```text
.symfix C:\Symbols\Microsoft
.sympath+ C:\Symbols\MyApp
.reload
```

最初に見るときは、ここでかなり差が出ます。**自前 PDB が見つからないと、自分のコード側が番地だらけになりやすい** です。

### 9.4. まずは自動解析を見る

最初の一歩としては、これで十分です。

```text
!analyze -v
```

そのうえで、

- どの例外コードか
- faulting module は何か
- 自分のコードがどこまでスタックに見えているか
- 例外スレッド以外に怪しい待ちや詰まりがないか

を順に見ます。

なお、**ミニダンプでは保存されていないメモリに踏み込む解析はできません**。そこが足りなければ、次回はフルダンプに切り替える、という考え方になります。

## 10. よくあるはまりどころ

最後に、入門でよく転ぶポイントをまとめます。

### 10.1. ダンプは取れたが、PDB がない

これはかなり多いです。ダンプ収集は成功していても、読む材料が不足します。  
**収集設定と同じタイミングで、PDB の保管設計も入れる** 方がよいです。

### 10.2. `DumpFolder` の ACL を見ていない

サービスや権限分離されたプロセスでは、ここで空振りしやすいです。  
**「そのプロセスが本当に書けるか」を先に確認** します。

### 10.3. フルダンプを本番機のシステムドライブへ出し続ける

これは容量事故の定番です。  
**保持数制限と出力先分離** は最初から入れます。

### 10.4. WER だけで hang も全部見ようとする

WER LocalDumps はまず crash に強いです。  
**hang や first chance exception は ProcDump の方が向いている** 場面があります。

### 10.5. `-e 1` を常時入れて、例外の嵐になる

first chance exception は便利ですが、ふつうに多いです。  
**件数制限を付ける、短時間だけ入れる、対象を限定する** のが現実的です。

### 10.6. アプリが独自クラッシュレポータを持っているのに、WER で取れる前提で進める

この場合は素直に **そのレポータの流儀に合わせるか、ProcDump / 自前へ寄せる** 方が速いです。

### 10.7. Debug build では取れたのに、本番相当の Release build で未確認

実際の現場で必要なのは Release build 側の観測です。  
**「本番に近い構成で 1 回取り切る」** を先にやっておくと、後でかなり楽になります。

## 11. まとめ

クラッシュダンプは、再現率の低い障害に対してかなり強い観測点です。特に Windows アプリで COM、P/Invoke、native DLL、長時間運転が絡むなら、最初から「落ちたら何が残るか」を決めておく価値があります。

おすすめの順番はシンプルです。

1. **まず WER LocalDumps をアプリ単位で入れる**
2. **必要なら ProcDump を足す**
3. **さらに制御したくなったら、別プロセス前提で `MiniDumpWriteDump` を使う**

この順で進めると、大きく外しにくいです。

「顧客環境でしか落ちない」「ダンプは取れたがどこから読めばよいか分からない」「native と managed の境界で壊れていそう」といった場合は、ダンプ単体で戦わず、ログ、シンボル、版情報、再現条件を合わせて切り分けると前に進みやすいです。

## 12. 参考資料

- [ユーザーモード ダンプの収集 - Win32 apps | Microsoft Learn](https://learn.microsoft.com/ja-jp/windows/win32/wer/collecting-user-mode-dumps)
- [ProcDump v11.1 - Sysinternals | Microsoft Learn](https://learn.microsoft.com/en-us/sysinternals/downloads/procdump)
- [MiniDumpWriteDump function (minidumpapiset.h) - Win32 | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/api/minidumpapiset/nf-minidumpapiset-minidumpwritedump)
- [User-mode dump files - Windows drivers | Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/user-mode-dump-files)
- [ユーザー モード ダンプ ファイルの分析 - Windows drivers | Microsoft Learn](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/debugger/analyzing-a-user-mode-dump-file)
- [Windows デバッガーをインストールする - Windows drivers | Microsoft Learn](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/debugger/)
- [Symbol path for Windows debuggers - Windows drivers | Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/symbol-path)
- [!analyze (WinDbg) - Windows drivers | Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-analyze)
- [Troubleshoot processes by using Task Manager - Windows Server | Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/windows-server/support-tools/support-tools-task-manager)
- [Enabling Postmortem Debugging - Windows drivers | Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/enabling-postmortem-debugging)

## 関連トピック

- [技術トピック | KomuraSoft](https://comcomponent.com/topics/)
- [不具合調査 / 長期稼働テーマ | KomuraSoft](https://comcomponent.com/topics/bug-investigation-long-run/)
- [想定していない例外が起きたとき、アプリを終了させるべきか継続すべきか - まず見る判断表 | KomuraSoft Blog](https://comcomponent.com/blog/2026/03/16/005-unexpected-exception-exit-or-continue-decision-table/)
- [産業用カメラ制御アプリが1か月後に突然落ちるとき（前編） - ハンドルリークの見つけ方と長期稼働向けログ設計 | KomuraSoft Blog](https://comcomponent.com/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/)
- [産業用カメラ制御アプリが1か月後に突然落ちるとき（後編） - Application Verifier とは何かと異常系テスト基盤の作り方 | KomuraSoft Blog](https://comcomponent.com/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/)

## このテーマの相談先

### [不具合調査・原因解析 | KomuraSoft](https://comcomponent.com/services/bug-investigation/)

クラッシュダンプ、ログ、再現条件を合わせて切り分ける流れは、不具合調査・原因解析と相性のよいテーマです。  
特に、現場でしか起きないクラッシュ、長時間運転後にだけ起きる障害、COM / P/Invoke / native DLL 境界を含む不安定化では、観測の入れ方そのものが重要になります。

### [技術相談・設計レビュー | KomuraSoft](https://comcomponent.com/services/technical-consulting/)

本番で何を採取するか、ダンプとログをどう設計へ織り込むか、権限や保管方針まで含めて整理したい場合は、技術相談・設計レビューのテーマとして進めやすいです。

## 著者プロフィール

### [小村 豪 | KomuraSoft](https://comcomponent.com/profile/go-komura/)

KomuraSoft 代表。  
Windows ソフト開発、技術相談、不具合調査を中心に、既存資産が残る案件や、原因が見えにくい障害調査に強みがあります。
