---
title: "Windowsで異なるバージョンのプログラムの実行速度をいかに比較するか。電源モード等の環境の揃え方から限界まで"
date: 2026-03-16 10:00
lang: ja
translation_key: windows-benchmark-comparing-program-versions
tags:
  - Windows
  - Benchmark
  - Performance
  - Profiling
  - Power Management
description: "Windows でプログラムのバージョン差を比較するときに、power mode、power plan、熱、バックグラウンドノイズ、測定指標、ETW / WPR まで含めて再現性の高い手順を整理します。"
consultation_services:
  - id: technical-consulting
    reason: "性能比較の設計、計測条件の揃え方、ETW / WPR での掘り下げまで含めて、技術相談・設計レビューと相性がよいテーマです。"
  - id: bug-investigation
    reason: "バージョン間で速い・遅いの差が出たときに、電源条件、熱、バックグラウンドノイズ、実装差のどこが原因か切り分ける流れは、不具合調査・原因解析として進めやすいです。"
---

Windows でプログラムのバージョン A と B を比較したい。  
そのとき一番やってはいけないのは、同じマシンで 1 回ずつ実行して「B のほうが 8% 速いっぽい」と言ってしまうことです。

その 8% は、本当にコード差かもしれません。  
でも実際には、**電源モード、power plan、熱、バックグラウンド更新、検索インデックス、ウイルススキャン、アフィニティ、実行順序、キャッシュ状態**のどれかだった、というのが Windows ベンチあるあるです。なかなか泥くさい世界です。

この記事では、Windows 上で異なるバージョンのプログラムの実行速度を、**できるだけコード差に近い形で**比較する方法を整理します。  
対象は主に Windows 11 を想定していますが、`powercfg` や `start` などの大半は Windows 10 でも同様に使えます。

## まず結論

先に結論だけ言うと、再現性を上げるコツは次の 6 つです。

1. **「何を比較したいか」を先に決める**  
   コード差を見たいのか、実ユーザー体験を見たいのかで、揃えるべき環境が変わります。

2. **power mode と power plan を別物として記録する**  
   Windows ではここを雑に扱うと、比較が OS の省電力方針比較になりがちです。

3. **冷えた 1 回目と、温まった後の定常状態を分ける**  
   初回だけ速い・後半だけ遅い、は珍しくありません。

4. **A→B→A→B のように交互に回す**  
   A を先に全部回してから B を回すと、熱やバックグラウンド状態の偏りを食らいます。

5. **平均だけでなく中央値とばらつきを見る**  
   1 個の外れ値で世界観が壊れます。平均は思ったより脆いです。

6. **差が小さいなら ETW / WPR で原因まで掘る**  
   体感で議論すると、だいたい霧の中で殴り合いになります。

## 何を比較したいのかを最初に決める

「速度比較」と一口に言っても、実は 2 種類あります。

### 1. コード差を見たい比較

アルゴリズム変更、データ構造変更、コンパイラ最適化、ランタイム更新などによって、**実装そのものが速くなったか**を知りたい比較です。

この場合は、環境ノイズをできるだけ削ります。  
ベンチ専用セッション、power mode 固定、通知停止、検索インデックスや同期の抑制、必要なら clean boot までやります。

### 2. 実ユーザー体験を見たい比較

配布後にユーザーが普段の Windows 上で体感する速さを知りたい比較です。

この場合は、**現実に存在するノイズを全部消してはいけません**。  
OneDrive 同期、Defender、通知、通常の電源設定などを含んだ「それっぽい日常環境」で比較したほうが、現実に近い結果になります。

この 2 つを混ぜると、結論がねじれます。  
「ラボでは 12% 速いのに、現実では誤差」「現実では速いのに、CPU 時間では変わらない」みたいなことが普通に起きます。

## Windows で結果がぶれる主因

まず、何が結果をぶらすのかを雑に一覧化しておきます。

| 層 | ぶれ要因 | 典型例 |
| --- | --- | --- |
| ハードウェア | CPU / GPU、メモリ、SSD、冷却 | ノート PC の薄さ、冷却台の有無 |
| ファームウェア | BIOS / UEFI、OEM 制御 | 省電力ポリシー、ファン制御 |
| OS | Windows build、ドライバ、更新状態 | 同じ PC でも更新後に挙動が変わる |
| 電源 | AC / DC、power mode、power plan | バッテリー駆動だと別世界 |
| 熱 | 室温、ファン、直前の負荷 | 1 回目だけターボ、後半で失速 |
| バックグラウンド | Update、Defender、同期、通知 | 実行中にスキャンや同期が走る |
| スケジューリング | 優先度、アフィニティ、NUMA | マシン次第で CPU 配置が変わる |
| データ / キャッシュ | OS キャッシュ、アプリキャッシュ | 初回だけ遅い、2 回目以降だけ速い |
| ビルド条件 | Debug / Release、PGO、ログ有無 | そもそも別物を比べている |

要するに、**「同じ Windows マシン」でも、条件が揃っていなければ別の実験**です。

## power mode と power plan は分けて考える

ここはかなり重要です。

Windows には、設定アプリの **Power mode** と、従来の **Power plan**（`powercfg` で見える電源プラン）がいます。  
見た目が似ているので一緒くたにされがちですが、雑に扱うと比較がぐちゃっとします。

Windows の設定アプリでは、`Settings > System > Power & battery` から Power mode を選べます。  
Microsoft のドキュメントでは、Plugged in / On Battery ごとに `Best power efficiency`、`Balanced`、`Best performance` を切り替えられるとされています。さらに、Power mode は変わると背後の電源関連設定や PPM（Processor Power Management）の挙動にも影響します。つまり、ここが違うだけでコア駐車や性能スケーリングの方針が変わり得ます。

一方、Power plan は `Balanced`、`High performance` などの伝統的な電源プランです。  
`powercfg /list` や `powercfg /getactivescheme` で確認できます。

ここでややこしいのは、Windows には **power mode のオーバーレイ**と**power plan**の両方があることです。  
なので、ベンチ結果には最低でも次を記録してください。

- AC かバッテリーか
- Power mode が何か
- Active power plan が何か

この 3 つを書いていないベンチ結果は、後から見るとかなりつらいです。

### まず固定すべき電源条件

1. **ノート PC は必ず AC 接続で比較する**  
   バッテリー運用は、意図しない制限が入りやすいです。

2. **Power mode を固定する**  
   ベンチ用途なら、まず `Best performance` を試します。

3. **Active power plan を記録する**  
   `powercfg` で現在値を残します。

```powershell
powercfg /list
powercfg /getactivescheme
```

4. **必要なら High performance に切り替える**

```powershell
# Balanced
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e

# High performance
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
```

### 「High performance が出ない」は普通にある

ここもハマりどころです。  
Microsoft のドキュメントでは、**Modern Standby 対応デバイスでは Balanced、または Balanced から派生したプランしか許可されない**とされています。  
なので、「High performance が見当たらない、壊れた？」ではなく、**その機種の設計上そうなっている**可能性があります。

また、Microsoft は「Power mode が変更できない場合、custom power plan が選ばれているかもしれないので、まず Balanced を選んでみる」と案内しています。Power mode の UI が動かないときは、ここを疑うのが早いです。

## バックグラウンドノイズを潰す

Windows は働き者です。こちらが静かにベンチしたい時にも、裏でいろいろやってくれます。

### まずは再起動して、落ち着くまで待つ

設定変更後は一度再起動し、ログイン後すぐには走らせず、数分待ちます。  
起動直後は、更新、インデックス、同期、Defender、各種常駐がまだ暴れています。

### serious な比較なら clean boot を使う

Microsoft は、clean boot によって最小限のスタートアップ構成にできる手順を案内しています。  
`msconfig` で Microsoft 以外のサービスを止め、Task Manager で Startup apps を無効化する方法です。

これは**ノイズを減らす**には強力です。  
ただし、日常利用環境とは離れるので、「コード差を見るためのラボ比較」で使うのが向いています。

### 通知を黙らせる

Windows の通知バナーは、軽く見えて意外と邪魔です。  
視覚的に邪魔なだけでなく、実行タイミングやフォーカス、裏のアプリ活動を変えることがあります。

`Do not disturb` を手動で有効にするか、少なくともベンチ中は通知を切ります。

### 検索インデックスと同期を抑える

ベンチ対象が大量ファイルを読む、生成物を大量に書く、ソースツリーを何度も作り直す、というタイプなら、検索インデックスやクラウド同期が地味に刺さります。

- ベンチ用のディレクトリを検索対象から外す
- OneDrive / Dropbox / Google Drive などの同期を止める
- ブラウザ、Teams、Discord、Slack を閉じる

このへんは派手さはないですが、効くときはかなり効きます。

## 熱を揃えない比較は、だいたい熱を比べている

CPU や GPU は、冷えているときと温まった後で別の生き物になります。  
特にノート PC、薄型ミニ PC、小型デスクトップは顕著です。

### 守るべきルール

- 室温をできるだけ揃える
- ノート PC の置き方を固定する
- AC アダプタ、ドック、外部ディスプレイ構成を固定する
- ベンチの前に重い作業をしない
- 初回実行と定常状態を分けて測る

### 実行順序は交互にする

A を 10 回やってから B を 10 回、は避けます。  
熱、キャッシュ、バックグラウンド活動の偏りが載るからです。

おすすめは次のどれかです。

- `A B A B A B ...`
- `A B B A A B B A ...`
- ランダム順序を事前生成して、その順に回す

## 何を測るかで「速い」の意味は変わる

「速い」を 1 個の数に押し込むと、だいたい事故ります。  
Windows で見るべき代表的な指標は次の 3 つです。

### 1. Wall-clock time（実時間）

ユーザーが待つ時間です。  
エンドツーエンドの体感に一番近いので、まず最初に見る値はこれです。

Windows では `QueryPerformanceCounter` (QPC) が高分解能の時刻取得に使えます。  
managed code なら `Stopwatch` 系を使うのが基本です。  
`DateTime.Now` でミリ秒を眺めるのは、さすがにちょっと無防備です。

### 2. CPU time（ユーザー + カーネル時間）

`GetProcessTimes` で取得できる、プロセスが実際に CPU を使った時間です。

これは**計算効率を見る**のに便利です。  
たとえば wall-clock では速くなったのに CPU time が変わらないなら、キャッシュ、I/O、待ち時間、スケジューリングが効いている可能性があります。

### 3. Cycle count（CPU サイクル数）

`QueryProcessCycleTime` で、プロセス全体の CPU サイクル数を取れます。

これも CPU work を見る指標ですが、wall-clock とは別の面を見せてくれます。  
特に「待ち時間は同じだが、計算部分は軽くなっているのか」を見たいときに便利です。

## priority、affinity、NUMA は最後の手段

このあたりは効くことがあります。  
でも、効くからといって最初から触ると、別の現象を作りやすいです。

### まずは普通に測る

デフォルト状態で差が出るなら、その差自体に価値があります。  
いきなり `/high` や `/affinity` を入れると、**「実際の Windows では起きない条件」**を持ち込むことになります。

### 使うなら、目的を明確にする

- **/high**: 他のプロセスの邪魔を受けにくくしたい
- **/affinity**: CPU 配置を固定して比較したい
- **NUMA 制御**: 大規模マシンでメモリ局所性まで揃えたい

Windows の `start` コマンドは、priority class や affinity mask を付けて起動できます。

```cmd
start "" /high /wait myapp.exe --bench case1.json
start "" /affinity F /high /wait myapp.exe --bench case1.json
```

### ただし /realtime はやめる

`/realtime` は使えますが、**使わないほうがいい**です。  
ノイズ除去ではなく、別の事故を作る方向に働きがちです。

## 測定手順のおすすめ

ここまでを踏まえた、実運用しやすい手順をまとめます。

### ラボ寄りの比較手順

1. **比較対象を固定する**
   - commit hash / build number
   - compiler / runtime version
   - Debug / Release
   - ログ、assert、トレース有無
2. **マシン条件を固定する**
   - Windows build
   - BIOS / UEFI version
   - driver version
   - AC 接続
   - 室温、設置方法
3. **電源条件を固定する**
   - Power mode を決める
   - Active power plan を記録する
4. **再起動する**
5. **ベンチ前に数分待つ**
6. **必要なら clean boot**
7. **warm-up を入れる**
8. **A / B を交互に回す**
9. **回数を確保する**
10. **中央値・最小・最大・p95 を残す**
11. **raw data を保存する**
12. **差が小さければ ETW / WPR を取る**

## 記録しておくと後で助かる項目

ベンチの CSV や JSON には、少なくとも次を残しておくと強いです。

```text
timestamp,version,scenario,elapsed_ms,user_ms,kernel_ms,cycles,power_mode,power_plan,ac_or_dc,room_temp_c,notes
```

可能なら、さらに次もあると便利です。

```text
cpu_package_temp_start_c,cpu_package_temp_end_c,affinity_mask,priority_class,windows_build,driver_version
```

ベンチは、**測ること**より**後で解釈できること**のほうが大事だったりします。

## 平均だけでなく、中央値と分布を見る

平均は便利ですが、Windows ベンチでは簡単に壊れます。  
1 回だけ Defender が入った、通知が出た、別プロセスが SSD を叩いた、というだけで平均が持っていかれます。

おすすめは次です。

- **中央値**: まずこれを見る
- **p95 / p99**: tail が悪化していないかを見る
- **min / max**: 外れ方を見る
- **箱ひげ図や散布図**: 差が小さいときに役立つ

## 差が出たときの読み方

結果の解釈は、組み合わせで見ると分かりやすいです。

### wall-clock だけ速い

I/O、待ち時間、キャッシュ、スケジューリングの改善かもしれません。

### CPU time も cycle も下がっている

実装そのものが軽くなっている可能性が高いです。

### 1 回目だけ遅い / 速い

cold / warm の差です。起動・初期化・キャッシュ生成・JIT を疑います。

### 回を重ねるほど遅くなる

熱、スロットリング、メモリ圧迫、バックグラウンド活動を疑います。

## ETW / WPR で「なぜ速いか」まで掘る

差が小さい、あるいは理由が読めないときは、Windows の ETW（Event Tracing for Windows）系ツールに進むのが王道です。

Microsoft の `Windows Performance Recorder` (WPR) は ETW ベースの記録ツールで、`Windows ADK` に含まれています。  
CPU、I/O、context switch、ページフォールトなどをまとめて取れます。

最低限ならこんな感じです。

```cmd
wpr -start CPU -filemode

REM ここでベンチを実行する

wpr -stop trace.etl
```

この段階まで来ると、  
「B のほうが 3% 速い」ではなく、  
「B は lock 待ちが減って ready time が下がっている」  
「A は file open が増えて cold start が遅い」  
のように、理由付きで話せるようになります。

## まとめ

Windows でバージョン違いのプログラムを比較するときに、本当に効くのは派手な裏技ではありません。  
大事なのは、次のような**地味だけど再現性に効く作法**です。

- **AC / Power mode / power plan を固定して記録する**
- **cold と warm を分ける**
- **A / B を交互に回す**
- **中央値と分布を見る**
- **必要なら clean boot**
- **差が小さければ ETW / WPR で理由まで掘る**

そして一番大事なのは、**何を固定して、何を固定しなかったかを結果と一緒に書くこと**です。  
ベンチは速さの比較であると同時に、実験条件の記録でもあります。

条件の書かれていない高速化報告は、たまに当たる占いくらいには面白いのですが、再現性という意味ではかなり頼りないです。  
逆に条件がきちんと書かれていれば、たとえ差が小さくても、その結果にはちゃんと価値があります。

## 参考資料

- [Microsoft Support: Change the power mode for your Windows PC](https://support.microsoft.com/en-us/windows/change-the-power-mode-for-your-windows-pc-c2aff038-22c9-f46d-5ca0-78696fdf2de8)
- [Microsoft Learn: Power Policy Settings](https://learn.microsoft.com/en-us/windows/win32/power/power-policy-settings)
- [Microsoft Learn: Customize the Windows performance power slider](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-power-slider)
- [Microsoft Learn: Powercfg command-line options](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
- [Microsoft Support: How to perform a clean boot in Windows](https://support.microsoft.com/en-us/topic/how-to-perform-a-clean-boot-in-windows-da2f9573-6eec-00ad-2f8a-a97a1807f3dd)
- [Microsoft Support: Notifications and Do Not Disturb in Windows](https://support.microsoft.com/en-us/windows/notifications-and-do-not-disturb-in-windows-feeca47f-0baf-5680-16f0-8801db1a8466)
- [Microsoft Support: Search indexing in Windows](https://support.microsoft.com/en-us/windows/search-indexing-in-windows-da061c83-af6b-095c-0f7a-4dfecda4d15a)
- [Microsoft Learn: Configure custom exclusions for Microsoft Defender Antivirus](https://learn.microsoft.com/en-us/defender-endpoint/configure-exclusions-microsoft-defender-antivirus)
- [Microsoft Support: Device Security in the Windows Security App](https://support.microsoft.com/en-us/windows/device-security-in-the-windows-security-app-afa11526-de57-b1c5-599f-3a4c6a61c5e2)
- [Microsoft Learn: QueryPerformanceCounter function](https://learn.microsoft.com/en-us/windows/win32/api/profileapi/nf-profileapi-queryperformancecounter)
- [Microsoft Learn: Acquiring high-resolution time stamps](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)
- [Microsoft Learn: GetProcessTimes function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes)
- [Microsoft Learn: QueryProcessCycleTime function](https://learn.microsoft.com/en-us/windows/win32/api/realtimeapiset/nf-realtimeapiset-queryprocesscycletime)
- [Microsoft Learn: start command](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/start)
- [Microsoft Learn: SetPriorityClass function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass)
- [Microsoft Learn: SetProcessAffinityMask function](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setprocessaffinitymask)
- [Microsoft Learn: Processor Groups](https://learn.microsoft.com/en-us/windows/win32/procthread/processor-groups)
- [Microsoft Learn: Windows Performance Recorder](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-recorder)
- [Microsoft Learn: WPR Command-Line Options](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpr-command-line-options)
