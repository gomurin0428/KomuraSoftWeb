# Windows Forms、WPF、WinUI のどれにするか - 新規開発、既存資産、配布、UI 表現の判断表

Windows のデスクトップアプリを C# / .NET で作るとき、
地味に毎回ややこしいのが **WinForms、WPF、WinUI のどれを選ぶか** です。

ここで危ないのは、

- いちばん新しいから WinUI
- いちばん慣れているから WinForms
- なんとなく中間っぽいから WPF

みたいな、ふわっとした選び方です。

実務では、見るべき軸はもう少しはっきりしています。

- **新規開発か、既存資産の延長か**
- **画面が入力フォーム中心か、表現力が必要か**
- **Windows らしいモダンな UI が製品価値そのものか**
- **配布・更新・企業内運用をどうするか**
- **チームが Designer 文化なのか、XAML / MVVM 文化なのか**

この記事では、このあたりを **判断表として一枚で見やすく整理** します。  
なお、この記事でいう **WinUI は主に WinUI 3 + Windows App SDK** を指します。[^winui-overview][^winappsdk-overview]

また、この 3 つは **全部 Windows 専用** です。  
macOS / Linux も視野に入るなら、そもそも問題設定が違います。[^winforms-overview][^wpf-overview][^winui-overview]

## 目次

1. まず結論（ひとことで）
2. この記事でいう 3 つの技術
3. 一枚で見る判断表
4. 観点別の比較表
5. それぞれ、どういう案件に向くか
   - 5.1 WinForms
   - 5.2 WPF
   - 5.3 WinUI
6. よくある判断ミス
7. 既存アプリを前提にするときの見方
8. 迷ったときに最後に見る 5 問
9. まとめ
10. 参考資料

* * *

## 1. まず結論（ひとことで）

先にかなり雑に、でも実務で使いやすい言い方をすると、こうです。

- **既存 WinForms アプリ** が大きいなら、まずは **WinForms 継続** を基本に見ます
- **既存 WPF アプリ** が大きいなら、まずは **WPF 継続** を基本に見ます
- **新規の小〜中規模な社内ツール** で、標準コントロール中心・入力画面中心・素早く作りたいなら、**WinForms** はまだかなり強いです[^winforms-overview][^winforms-designer]
- **新規の中〜大規模な業務アプリ** で、画面数が多く、データバインディング、スタイル、テンプレート、コマンド、MVVM をちゃんと使いたいなら、**WPF** がいちばん無難なことが多いです[^wpf-overview][^wpf-data][^wpf-command]
- **新規の Windows 専用製品** で、モダンな Windows UI、Fluent、最新の Windows 体験が製品価値に直結するなら、**WinUI** が有力です[^winui-overview][^winappsdk-overview]
- **最新の Windows API を使いたい** だけなら、**WinUI 必須ではありません**。WPF / WinForms でも Windows App SDK の機能を取り込めます[^winappsdk-overview][^winappsdk-existing-wpf][^winappsdk-existing-winforms][^windows-faq]
- **「あとで少しずつ WinUI を差し込めばいい」** を前提に選ぶのは、少し危ないです。段階移行の話は、思ったより泥くさいです[^windows-faq][^xaml-islands]

要するに、だいたい次です。

1. **既存資産が大きいなら、その系譜をまず残す**
2. **新規で、標準フォームを速く作るなら WinForms**
3. **新規で、長く育つ Windows 業務アプリなら WPF**
4. **新規で、モダン Windows UI 自体が要件なら WinUI**
5. **Windows App SDK を使いたいだけなら、いきなり全部 WinUI にしない**

フレームワーク選定は、UI 技術の選定であると同時に、
**配布・運用・学習コスト・移行コストの選定** でもあります。  
ここを「新しい / 古い」だけで決めると、あとで静かに効いてきます。いやな形で。

## 2. この記事でいう 3 つの技術

最初に、言葉を少しそろえます。

| 技術 | ざっくりいうと | 強い軸 |
|---|---|---|
| WinForms | Visual Studio の Designer で素早くフォームを組みやすい、Windows 向けの伝統的な .NET デスクトップ UI | 速い画面作成、標準コントロール、既存資産の活用 |
| WPF | XAML、データバインディング、スタイル、テンプレート、コマンドを使って表現力のある UI を作りやすい Windows 専用 UI | 中〜大規模業務アプリ、MVVM、画面の整理しやすさ |
| WinUI | Windows App SDK 上のモダンな Windows ネイティブ UI | Fluent、最新 Windows 体験、高 DPI、モダンな製品 UI |

WinForms は、Microsoft Learn でも **コントロール、グラフィックス、データ バインディング、ユーザー入力を備え、Visual Studio のドラッグ＆ドロップ Designer でアプリを作りやすい** フレームワークとして説明されています。[^winforms-overview]

WPF は、**解像度非依存のベクターベース描画**、**XAML**、**データバインディング**、**スタイル / テンプレート**、**2D / 3D**、**アニメーション** まで含む表現力の高い UI フレームワークです。[^wpf-overview]

WinUI は、**Windows App SDK の一部** で、**高 DPI、モダンな入力、スムーズなアニメーション、Fluent 系の体験** を前提にした、今の Windows 向け UI フレームワークです。[^winui-overview][^winappsdk-overview]  
また、data binding / MVVM の導線も普通に持っています。[^winui-mvvm]

ここで大事なのは、**Windows App SDK と WinUI は同じではない** ということです。  
WinUI は Windows App SDK の UI フレームワーク部分ですが、Windows App SDK 自体は **WPF / WinForms / Win32 の既存アプリにも追加できます**。[^winappsdk-overview][^windows-faq]

なので、

- **WinUI を使う**
- **Windows App SDK の機能を使う**

は、似ているようで別の判断です。  
ここが混ざると、会議室で話がちょっと霧深くなります。

## 3. 一枚で見る判断表

まずは、いちばん実務で使いやすい表を置きます。

| 状況 | まず選ぶもの | 理由 |
|---|---|---|
| 既存 WinForms アプリの改修・延命・.NET への更新 | WinForms 継続 | 既存画面、Designer 資産、コントロール資産を活かしやすい |
| 既存 WPF アプリの改修・延命・.NET への更新 | WPF 継続 | XAML、Binding、MVVM、画面構造をそのまま活かしやすい |
| 新規、社内ツール、設定画面、管理画面、入力フォーム中心 | WinForms | 標準コントロール中心なら立ち上がりが速い |
| 新規、画面数が多い、状態が複雑、スタイル / テンプレート / MVVM を使いたい | WPF | 画面の責務分離と UI の整理がしやすい |
| 新規、Windows らしいモダン UI 自体が要件 | WinUI | Fluent や最新の Windows 体験に寄せやすい |
| 既存 WPF / WinForms のまま、Toast / Windowing / App Lifecycle などを使いたい | 現行フレームワーク + Windows App SDK | 最新 Windows 機能のために UI 全面移行までは不要なことが多い |
| COM / ActiveX / 古いサードパーティコントロール依存が濃い | 既存フレームワーク寄り | UI 以前に依存関係の移行コストが大きい |
| 配布・更新・企業内運用の都合を強く受ける | WPF / WinForms を優先検討、WinUI は配布設計を早めに確認 | WinUI は Windows App SDK / packaging 前提の論点を早めに見る必要がある |
| 将来クロスプラットフォーム化したい | この 3 つ以外を含めて再検討 | この 3 つは全部 Windows 専用 |

この表だけでかなり足りますが、悩みやすいのは次の 2 点です。

1. **新規の Windows 業務アプリで、WinForms と WPF のどちらに寄せるか**
2. **既存 WPF / WinForms があるのに、WinUI へ行くべきか**

この 2 点は、次の比較表を見ると整理しやすいです。

## 4. 観点別の比較表

ここは **公式な優劣表** ではなく、かなり実務寄りの比較です。

| 観点 | WinForms | WPF | WinUI |
|---|---|---|---|
| 小さめの入力フォームを素早く作る | ◎ | ○ | ○ |
| 標準コントロール中心の社内ツール | ◎ | ○ | △〜○ |
| データバインディング / MVVM との相性 | △ | ◎ | ○〜◎ |
| スタイル / テンプレート / 画面の表現力 | △ | ◎ | ◎ |
| 既存 Windows デスクトップ資産との親和性 | ◎ | ○ | △ |
| モダンな Windows らしさ | △ | ○ | ◎ |
| 既存画面の延命・段階改修 | ◎ | ◎ | △ |
| Windows App SDK 機能の追加だけをしたい | ○ | ○ | ◎ |
| 配布 / 更新 / 運用の設計の軽さ | ○ | ○ | △〜○ |
| 「新しく長く育つ Windows 専用製品 UI」を作る | △ | ○ | ◎ |

見方のコツは、**何が最強か** ではなく、**何がいちばん摩擦が少ないか** です。

たとえば、

- 社内の設定ツール
- 装置設定画面
- 一覧、明細、検索、設定、ボタン
- 外見より運用の安定と改修スピードが大事

なら、WinForms はまだかなり合理的です。

逆に、

- 画面数が多い
- 表示状態の切り替えが多い
- View とロジックを分けたい
- データの変化を UI に自然につなぎたい
- スタイル / テンプレートで UI を統制したい

なら、WPF がかなり効きます。[^wpf-data][^wpf-command]

そして、

- Windows 11 らしい見た目を前提にしたい
- Fluent をちゃんと活かしたい
- 高 DPI、タッチ、モダンなウィンドウ API を前提にしたい
- 新規で、Windows 専用製品として UI の印象も重要

なら、WinUI が自然です。[^winui-overview][^winappsdk-overview]

## 5. それぞれ、どういう案件に向くか

### 5.1 WinForms

WinForms は、変に軽く見られがちですが、
**標準コントロール中心の業務画面を速く作る** という一点では、今でもかなり強いです。[^winforms-overview][^winforms-designer]

特に向いているのは、たとえば次のようなものです。

- 社内向け設定ツール
- 装置・計測器・監視ツールの設定画面
- 管理画面、検索画面、一覧 + 明細
- 既存 WinForms 資産が大きい案件
- Designer で画面を組む文化が強いチーム

WinForms の強みは、難しい思想を持ち込まなくても **そこそこ速く完成物に近い画面が出る** ことです。  
フォーム、ボタン、ラベル、テキストボックス、データグリッド。  
この世界が主戦場なら、かなり戦えます。

ただし、弱いところもはっきりしています。

- 画面全体の見た目を大きく統一したい
- スタイルとテンプレートで UI を制御したい
- 複雑な状態変化をデータバインディング主体でさばきたい
- 画面ロジックをきれいに分離したい

このあたりは、WPF や WinUI のほうが素直です。

WinForms で大きいアプリを作ると、気を抜くと **イベントハンドラの密林** になりやすいです。  
なので、WinForms を選ぶなら、

- 画面責務を小さく保つ
- UserControl 単位で分ける
- Presenter / ViewModel 相当の境界を意識する
- 画面イベントに業務ロジックをべったり書かない

くらいは最初から決めておいたほうが平和です。

あと、実務でかなり大事なのは、**Windows App SDK を使いたいからといって WinForms を捨てる必要はない** ことです。  
公式にも、既存 WinForms アプリに Windows App SDK 機能を足す導線があります。[^winappsdk-existing-winforms][^windows-faq]

つまり、WinForms は

- UI はそのまま
- 必要な Windows 機能だけ近代化

という選び方ができます。  
ここはかなり現実的です。

### 5.2 WPF

WPF は、Windows デスクトップの .NET UI として見ると、
**いちばんバランスがよい中核** です。[^wpf-overview]

強みはかなり明確です。

- XAML で画面を宣言的に書ける
- Data Binding が強い
- Style / Template が使える
- Command が使える
- View とロジックを分けやすい
- 中〜大規模の画面を整理しやすい

WPF の公式ドキュメントでも、データバインディングは WPF の中心機能として説明されていて、コマンドも入力と実行ロジックを分ける仕組みとして整理されています。[^wpf-data][^wpf-command]

なので、たとえば次のような案件にかなり向きます。

- 画面数が多い業務アプリ
- 一覧、詳細、編集、検索、状態表示が多い
- 複数人で長く保守する Windows アプリ
- View とロジックを分けたい
- 将来の改修で、見た目と挙動の責務を分けておきたい
- WinForms だと画面がすぐ重たくなりそう

新規の Windows 専用業務アプリで迷ったとき、
**WPF は今でもかなり安全な第一候補** です。  
ここを「WPF は古いからなし」と切るのは、ちょっと乱暴です。

むしろ、

- 既存 WPF 資産がある
- 既存 XAML / MVVM の知見がある
- そこまで Fluent 最優先ではない
- でも WinForms より UI をきれいに設計したい

なら、WPF がいちばん筋がよいことは普通にあります。

もちろん、WPF にも癖はあります。

- XAML を凝りすぎると読みにくくなる
- 独自コントロールやテンプレート地獄に入ると保守が重い
- 「何でも Binding でやる」宗教に寄ると逆に追いにくい

このへんはあります。  
ただ、それは WPF が悪いというより、**表現力のある道具は雑に振ると反動も大きい** という話です。

WPF でも、Windows App SDK の一部機能を追加できます。  
つまり、**WPF のまま Windows 機能を近代化する** という道があります。[^winappsdk-existing-wpf][^windows-faq]

このため、

- WPF を全部捨てて WinUI へ全面移行

よりも、

- WPF を現行 .NET に寄せる
- 必要な Windows 機能だけ Windows App SDK で足す
- 新規の大きい機能から構成を整理する

のほうが、実務では勝ちやすいことがかなりあります。

### 5.3 WinUI

WinUI は、**新規の Windows 専用アプリ** を作るときのモダンな本命です。[^winui-overview][^winappsdk-overview]

公式には、

- 最新のハードウェアと入力向けに最適化
- 高 DPI
- スムーズなアニメーション
- Windows App SDK の一部

という位置づけです。[^winui-overview]

なので、こういう案件に向きます。

- Windows 専用の新規製品
- UI の印象や体験そのものが重要
- Fluent を素直に使いたい
- Windows 11 の現在地に寄せたい
- 新しいウィンドウ API や最新 Windows 体験を前提にしたい

WinUI を選ぶ理由がちゃんとある案件、というのは、
だいたい **「見た目が新しい」ではなく「Windows の今の体験を製品に取り込みたい」** 案件です。

一方で、注意点もあります。

#### 5.3.1 WinUI は「ただ新しい WPF」ではない

XAML を使うので近そうに見えますが、

- ベースの API
- コントロール周り
- プロジェクト構成
- デプロイ / packaging の考え方
- Windows App SDK との付き合い方

が違います。

つまり、**WPF からの気軽な置き換え先** と考えると、少し危ないです。

#### 5.3.2 WinUI を選ぶと、配布の話が前に出てくる

WinUI 3 アプリは **packaged が既定** です。  
一方で、Windows App SDK 自体は **packaged / unpackaged の両方** を扱います。[^packaging][^winui-quickstart][^winappsdk-overview]

ここで大事なのは、

- どう配布するのか
- ランタイムをどう入れるのか
- package identity が要るのか
- 社内配布か、Store か、MSIX か、既存 EXE / MSI 路線か

を、**早めに決めたほうがよい** ことです。

WinForms / WPF でも配布は大事ですが、WinUI はここが前景に出やすいです。  
UI を決めたつもりが、実は配布戦略を決めていた、というのがこの世界の少しややこしいところです。

#### 5.3.3 「既存 WPF / WinForms に少しずつ WinUI を混ぜる」は、先に実験する

ここは期待が膨らみやすいところです。  
ただ、Microsoft の FAQ でも、**UI フレームワークを完全に移行する準備ができていない限り WinUI は使えないことが多い**、という趣旨が書かれています。  
さらに XAML Islands まわりも、公式ドキュメントでは既存デスクトップアプリへの埋め込み導線が示される一方、Windows App SDK 1.4 のリリースノートでは **現時点では C++ アプリでの利用が主にテストされており、WPF / WinForms 向けの便利なラッパー要素は入っていない** とされています。[^windows-faq][^xaml-islands]

つまり、

- 「段階移行できそう」
- 「少しずつ埋めればよさそう」

は、**構想としては魅力的でも、案件の主戦略にする前に小さく検証したほうがよい** です。

WinUI は、

- **新規で始める**
- **Windows 専用製品として体験を作る**

ときにいちばん筋がよい。  
逆に、既存 WPF / WinForms の全面置換の受け皿としては、理由と検証が必要です。

## 6. よくある判断ミス

### 6.1 「最新だから WinUI」

これは分かりやすいですが、かなり危ないです。

新しい技術を選ぶ理由は、
**その技術でないと得られない価値があるか** で見たほうがよいです。

- モダンな Windows 体験が製品価値か
- Fluent を素直に使いたいか
- 新規製品か
- 配布 / 運用の前提を受け入れられるか

ここが yes なら WinUI はかなり有力です。  
逆に、単に「将来性がありそう」だけだと、コストの説明が弱いです。

### 6.2 「Windows App SDK を使いたいから WinUI にしないといけない」

これは誤解されやすいですが、違います。

Windows App SDK は、既存の WPF / WinForms にも足せます。  
公式 FAQ でも、WPF / MFC / WinForms アプリは WinUI と無関係な Windows App SDK API を使えると整理されています。[^windows-faq][^winappsdk-existing-wpf][^winappsdk-existing-winforms]

たとえば、

- App Lifecycle
- Windowing
- Toast Notifications

のような機能は、**今の UI を維持しながら取り込める** 場合があります。[^windows-faq]

### 6.3 「WPF / WinForms はもう終わっている」

ここも、雑に切らないほうがよいです。

WinForms も WPF も、現行の .NET 上でドキュメントと移行導線が継続していて、公式にも現役の Windows デスクトップ UI として扱われています。[^winforms-overview][^wpf-overview]

特に業務アプリでは、

- 既存資産
- サードパーティコントロール
- 画面数
- 帳票や印刷
- 装置連携
- 配布手順

のほうが、UI フレームワークの新しさより重いことが普通にあります。

### 6.4 「どうせなら全面リライト」

全面リライトは、技術選定ではなく **事業判断** に近いです。

既存アプリがあるなら、最初に見るべきは次です。

1. 何が本当に困っているのか
2. UI の問題なのか、アーキテクチャの問題なのか
3. 依存 DLL / COM / OCX / 帳票 / 配布が本当の重荷ではないか
4. UI を全部変えなくても困りごとは解けるか

UI リライトは派手ですが、コストも派手です。  
しかも、見た目は新しくなっても、周辺のややこしさはだいたい残ります。

### 6.5 「あとで XAML Islands で何とかなる」

この期待は理解できます。  
でも、**最初から救命ボート扱いしない** ほうが安全です。[^windows-faq][^xaml-islands]

段階移行は、

- 埋め込みたいコントロールは何か
- フォーカス、入力、DPI、テーマはどうなるか
- 実際にそのホスト構成が安定するか

を、先に小さく試したほうがよいです。

## 7. 既存アプリを前提にするときの見方

ここは、新規より既存のほうが大事です。

### 7.1 既存 WinForms があるなら

まずは、いきなり WinUI へ飛ぶ前に、次を見ます。

- 現行 .NET へ寄せられるか
- 64bit 化が必要か
- async / await、例外処理、設定、ログを整理できるか
- 画面分割や UserControl 化で保守性を上げられるか
- 必要な Windows 機能だけ Windows App SDK で足せるか

WinForms の問題に見えて、実際は

- 画面とロジックが混ざっている
- スレッド境界が雑
- 設定 / ファイル / COM / DB の責務が詰まっている

だけ、ということはかなりあります。

その場合、WinUI へ引っ越しても、問題が名前を変えて残るだけです。

### 7.2 既存 WPF があるなら

WPF は、既存資産を活かしやすいです。

- XAML 資産
- Binding
- Style / Template
- Command
- MVVM

このへんを捨てる理由は、かなり明確であるべきです。

たとえば、

- 製品 UI を全面刷新したい
- Fluent を主軸にしたい
- 新規モジュールを別製品として切り出す
- Windows 専用製品として新しい体験へ寄せたい

なら、WinUI の検討理由になります。  
でも、単に「WPF は古いから」だと弱いです。

### 7.3 本当に重いのは UI 以外のことが多い

実務では、しんどいのは案外このへんです。

- ActiveX / OCX
- COM interop
- 独自帳票
- 印刷
- Excel / Office 連携
- ネイティブ DLL
- 32bit / 64bit のねじれ
- インストーラ、権限、更新、署名

ここを軽く見ると、UI だけきれいにしても案件全体は軽くなりません。

なので、既存アプリの移行では、
**UI フレームワークだけを見るのではなく、依存境界ごと棚卸しする** ほうが先です。

## 8. 迷ったときに最後に見る 5 問

最終的に迷ったら、次の 5 問を順に見ます。

### 8.1 既存資産は大きいか

- 大きい → 既存系譜を基本維持
- 小さい / ない → 新規選定へ

### 8.2 そのアプリで「Windows らしいモダンな体験」は必須か

- 必須 → WinUI が有力
- そこまでではない → WPF / WinForms で十分か確認

### 8.3 画面は標準フォーム中心か、XAML 的な表現力が必要か

- 標準フォーム中心 → WinForms
- スタイル / テンプレート / Binding / MVVM が大事 → WPF

### 8.4 欲しいのは UI の全面刷新か、Windows 機能の追加か

- UI の全面刷新 → WinUI 検討
- 機能追加だけ → 現行 WPF / WinForms + Windows App SDK を先に検討

### 8.5 配布 / 更新 / 運用をどうするか、先に説明できるか

- まだ曖昧 → WinUI は早めに packaging / deployment を詰める
- 既存運用に強く乗せたい → WPF / WinForms のほうが摩擦が少ないことが多い

この 5 問でかなり絞れます。  
最後に雑にまとめると、こんな感じです。

- **速く作る社内フォーム** → WinForms
- **長く育つ Windows 業務アプリ** → WPF
- **新規のモダン Windows 製品 UI** → WinUI
- **既存を活かしつつ Windows 機能だけ近代化** → 現行フレームワーク + Windows App SDK

## 9. まとめ

WinForms、WPF、WinUI の選定は、
**新しい順に並べて一番右を取るゲーム** ではありません。

まず見るべきなのは、次の 4 つです。

1. **既存資産がどこにあるか**
2. **画面がフォーム中心か、表現力中心か**
3. **Windows らしいモダン UI が製品要件か**
4. **配布 / 更新 / 運用をどう回すか**

この 4 つが見えれば、だいたい次のように整理できます。

- **既存 WinForms を大きく持っているなら、まず WinForms 継続**
- **既存 WPF を大きく持っているなら、まず WPF 継続**
- **新規で標準フォーム中心なら WinForms**
- **新規で中〜大規模の Windows 業務アプリなら WPF**
- **新規でモダン Windows 体験そのものが要件なら WinUI**
- **Windows App SDK を使いたいだけなら、いきなり全部 WinUI にしない**

いちばん避けたいのは、

- 古いから捨てる
- 新しいから選ぶ
- 途中で何とかなるだろうで始める

の 3 つです。

Windows デスクトップは、見た目より **資産、配布、運用、依存関係** のほうが重い世界です。  
なので、選び方もキラキラ感より **摩擦の少なさ** を見るほうが、だいたい勝ちやすいです。

## 10. 参考資料

[^winforms-overview]: Microsoft Learn, “Windows フォームとは - Windows Forms” https://learn.microsoft.com/ja-jp/dotnet/desktop/winforms/overview/
[^winforms-designer]: Microsoft Learn, “What is Windows Forms Designer?” https://learn.microsoft.com/en-us/visualstudio/designers/windows-forms-designer-overview?view=visualstudio
[^wpf-overview]: Microsoft Learn, “Windows Presentation Foundation とは - WPF” https://learn.microsoft.com/ja-jp/dotnet/desktop/wpf/overview/
[^wpf-data]: Microsoft Learn, “Data binding overview - WPF” https://learn.microsoft.com/en-us/dotnet/desktop/wpf/data/
[^wpf-command]: Microsoft Learn, “Commanding Overview - WPF” https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/commanding-overview
[^winui-overview]: Microsoft Learn, “WinUI 3 - Windows apps” https://learn.microsoft.com/ja-jp/windows/apps/winui/winui3/ / Microsoft Learn, “Modernize your desktop apps for Windows” https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/
[^winui-mvvm]: Microsoft Learn, “Windows data binding and MVVM” https://learn.microsoft.com/en-us/windows/apps/develop/data-binding/data-binding-and-mvvm
[^winappsdk-overview]: Microsoft Learn, “Windows App SDK” https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/
[^winappsdk-existing-wpf]: Microsoft Learn, “WPF アプリでWindows App SDKを使用する” https://learn.microsoft.com/ja-jp/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/wpf-plus-winappsdk
[^winappsdk-existing-winforms]: Microsoft Learn, “Use the Windows App SDK in a Windows Forms (WinForms) app” https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/winforms-plus-winappsdk
[^windows-faq]: Microsoft Learn, “Windows 開発者向け FAQ” https://learn.microsoft.com/ja-jp/windows/apps/get-started/windows-developer-faq
[^packaging]: Microsoft Learn, “Packaging overview - Windows apps” https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/
[^winui-quickstart]: Microsoft Learn, “Quick start: Set up your environment and create a WinUI 3 project” https://learn.microsoft.com/en-gb/windows/apps/get-started/start-here
[^xaml-islands]: Microsoft Learn, “Windows App SDK 1.4 release notes” https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-4 / Microsoft Learn, “Windows App SDK” https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/
