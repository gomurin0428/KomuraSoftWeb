# あなたがいきなり COBOL のソースを読む羽目になった時に最低限知っておくべきこと - DIVISION / PIC / COMP-3 / COPY / PERFORM を先に整理

引き継ぎ、障害対応、ベンダー製パッケージの保守。そういう場面で、ある日いきなり COBOL のソースが飛んでくることがあります。

- ファイル名は `.cbl` や `.cpy`
- 変数名は全部大文字
- `01`、`05`、`77`、`88` が並ぶ
- `PIC S9(7)V99 COMP-3` みたいな、呪文と会計ソフトの中間みたいな記述が出る
- しかも `COPY` だらけで、開いたファイルだけでは全体が見えない

このあたりで脳が少し粉になります。

ただ、読むための地図はそこまで大きくありません。COBOL には処理系や製品ごとの差がありますが、既存業務システムを読むときに先に押さえるべき骨格はかなり共通です。この記事では、IBM 系や典型的な業務 COBOL を念頭に、**突然ソースを読むことになった人向けの最小セット**を整理します。

## 目次

1. まず結論（ひとことで）
2. COBOL はまず「データの形」の言語だと思う
3. 4つの DIVISION を先に見る
4. 固定形式の見た目にビビらない
5. DATA DIVISION の最低限
   - 5.1 レベル番号
   - 5.2 PICTURE
   - 5.3 USAGE / DISPLAY / COMP / COMP-3
   - 5.4 REDEFINES / OCCURS / COPY / FILLER
6. PROCEDURE DIVISION の最低限
   - 6.1 PERFORM
   - 6.2 IF / EVALUATE / スコープ
   - 6.3 READ / WRITE / CALL
7. COBOL の外側にあるもの
8. 最低限の読み順
9. よくある詰まりどころ
10. まず見る早見表
11. まとめ
12. 参考資料

* * *

## 1. まず結論（ひとことで）

先にかなり雑に、でも実務で役に立つ言い方をすると、こうです。

- COBOL は **ロジックの言語** である前に、かなり強く **レコード定義の言語** です
- `PROCEDURE DIVISION` だけ読んでも半分しか分かりません。まず `DATA DIVISION` を見ます
- `PIC` は **項目の形**、`USAGE` は **どういう表現で持つか** です
- `COMP-3` は packed decimal です。金額や件数の世界でよく出ます
- `88` は別変数というより、**直前項目の値に名前を付けた条件名** です
- `REDEFINES` は **同じメモリを別の形で見る** 仕組みです。コピーではありません
- `COPY` があるなら、いま開いているソースはまだ未完成です。copybook を見ないと全体が見えません
- `PERFORM`、`IF`、`EVALUATE`、`READ`、`WRITE`、`CALL` を追えれば、だいたいの流れは掴めます
- 古いソースは **列位置に意味がある固定形式** です。見た目の空白がただの飾りではありません[^ref-format]

要するに、**DIVISION、PIC、USAGE、COMP-3、REDEFINES、OCCURS、88、COPY、PERFORM**。このへんが読めると、迷子率がかなり下がります。

## 2. COBOL はまず「データの形」の言語だと思う

C# や Java の感覚で読むと、最初は `if` や `for` や関数呼び出しを追いたくなります。  
でも COBOL は、そこに行く前に **「このプログラムはどんなレコードを受け取り、どんなレコードを作り、どんなバッファを持っているのか」** を押さえたほうが早いです。

典型的な業務 COBOL は、だいたい次の流れです。

1. ファイルや DB からレコードを読む
2. `WORKING-STORAGE` 上の項目へ入れる
3. 条件分岐する
4. 別のレコードへ詰め替える
5. 書き出す

つまり、**アルゴリズムよりレイアウト** が先に立ちやすいです。

たとえば、こんな骨格です。

```cobol
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SAMPLE01.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT SALES-FILE ASSIGN TO ...

       DATA DIVISION.
       FILE SECTION.
       FD  SALES-FILE.
       01  SALES-REC.
           05  SALE-ID       PIC 9(8).
           05  SALE-AMOUNT   PIC S9(7)V99 COMP-3.

       WORKING-STORAGE SECTION.
       01  WS-EOF            PIC X VALUE 'N'.
           88  EOF           VALUE 'Y'.

       PROCEDURE DIVISION.
           PERFORM UNTIL EOF
               READ SALES-FILE
                   AT END
                       SET EOF TO TRUE
                   NOT AT END
                       PERFORM PROCESS-SALE
               END-READ
           END-PERFORM
           STOP RUN.
```

このコードを読むとき、最初に見るべきなのは `PERFORM` より先に `SALE-AMOUNT` の型や `EOF` の意味です。  
COBOL は、その順番で読むと急に静かになります。

## 3. 4つの DIVISION を先に見る

COBOL ソースは、まず大きく 4 つの `DIVISION` に分かれます。

| DIVISION | まず見ること |
|---|---|
| `IDENTIFICATION DIVISION` | プログラム名、古いコメント、由来 |
| `ENVIRONMENT DIVISION` | ファイル、外部資源、入出力の前提 |
| `DATA DIVISION` | レコード定義、作業領域、引数 |
| `PROCEDURE DIVISION` | 実際の処理手順 |

特に大事なのは次です。

- `FILE SECTION`  
  入出力ファイルのレコード定義がある
- `WORKING-STORAGE SECTION`  
  普段使う変数、フラグ、カウンタ、作業バッファがある
- `LOCAL-STORAGE SECTION`  
  呼び出しごとに初期化される領域があることがある
- `LINKAGE SECTION`  
  外から渡される引数や、サブプログラムの受け口があることがある

`LINKAGE SECTION` と `PROCEDURE DIVISION USING ...` が見えたら、**そのプログラムは単独完結ではなく、外からデータを受けて動く** 可能性が高いです。

## 4. 固定形式の見た目にビビらない

古い COBOL では、ソース 1 行の **列位置そのもの** に意味があります。これを知らないまま見ると、「なんで左に変な余白があるのか」が永遠に分かりません。[^ref-format]

固定形式では、ざっくりこうです。

- 1 - 6 列: 一連番号
- 7 列: indicator
- 8 - 11 列: Area A
- 12 - 72 列: Area B

7 列目は特に大事です。

- `*` または `/` : コメント行
- `-` : 継続行
- `D` : debugging line
- `*>` : 途中にも書けるコメント

見た目の圧を下げるために、かなり雑に図にするとこうです。

```text
1234567 8901 23456789012345678901234567890
      * コメント
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SAMPLE01.
```

ここでの空白は、現代的な意味での「整形」ではなく、部分的に構文です。  
エディタでタブ変換したり、左に寄せたり、雑にコピペすると普通に壊れます。  
古いソースを見るときは、**まずそのファイルが fixed format なのか free format なのか** を疑ってください。fixed なのに modern formatter を当てると、かなり景気よく爆発します。

## 5. DATA DIVISION の最低限

### 5.1 レベル番号

COBOL のデータ定義は、インデントではなく **レベル番号** で階層を作ります。[^level-numbers]

```cobol
       01  WS-ORDER.
           05  WS-ORDER-ID    PIC 9(8).
           05  WS-AMOUNT      PIC S9(7)V99 COMP-3.
           05  WS-STATUS      PIC X.
               88  WS-OK      VALUE '0'.
               88  WS-ERROR   VALUE '9'.

       77  WS-COUNT           PIC 9(4).
```

最低限これだけ覚えておけば十分です。

- `01` : ひとまとまりの最上位レコード、グループ
- `02` - `49` : その下の階層
- `77` : 独立した単項目
- `88` : condition-name。直前項目の値に名前を付ける[^cond88]
- `66` : `RENAMES` 用。遭遇率は高くないけれど存在はする

大事なのは、`88` を **bool の別変数** だと思わないことです。  
`WS-OK` という領域が別にあるのではなく、`WS-STATUS` が `'0'` のときに `WS-OK` という名前で読める、という感じです。

もう 1 つ大事なのは、**階層を決めるのは空白ではなくレベル番号** だということです。  
見た目の字下げは参考になりますが、最終的に信じるべきは `01 / 05 / 10 / 88` のほうです。[^level-numbers]

### 5.2 PICTURE

`PIC` は、その項目の **形** を表します。  
いちばんよく見るのは次です。

| 記法 | ざっくり意味 |
|---|---|
| `X` | 文字 |
| `9` | 数字 |
| `S` | 符号付き |
| `V` | 小数点は論理上だけ持つ |
| `X(10)` | 10 文字 |
| `9(5)` | 5 桁数値 |
| `S9(7)V99` | 符号付き、整数 7 桁 + 小数 2 桁 |

たとえば、

- `PIC X(10)` → 10 文字
- `PIC 9(5)V99` → 5 桁整数 + 2 桁小数
- `PIC S9(7)V99` → 符号付き 7 桁整数 + 2 桁小数

です。

ここで特に大事なのは `V` です。  
`V` は **実際の `.` 文字を持ちません**。  
`PIC 9(5)V99` は「小数点 2 桁の数」として扱われますが、データ上にドット文字が入っているわけではありません。  
なので、ファイルやダンプを「見た目の文字列」として解釈すると、だいたいこけます。

### 5.3 USAGE / DISPLAY / COMP / COMP-3

`PIC` が形だとすると、`USAGE` は **どういう表現で保持するか** です。  
最低限、次だけ押さえればかなり読めます。[^numeric-repr][^comp3]

| 記法 | ざっくり意味 | 読むときの注意 |
|---|---|---|
| `DISPLAY` | 文字として見える外部 10 進 | mainframe では EBCDIC 前提のことがある[^ebcdic] |
| `COMP` / `BINARY` | 2進数 | 見た目の桁数と内部表現は別 |
| `COMP-3` / `PACKED-DECIMAL` | packed decimal | 文字として読むと壊れて見える |

たとえば、

```cobol
       01  WS-AMOUNT-DISP   PIC S9(7)V99.
       01  WS-AMOUNT-BIN    PIC S9(7) COMP.
       01  WS-AMOUNT-PACK   PIC S9(7)V99 COMP-3.
```

この 3 つは、全部「数値」ですが、**中身の持ち方が違います**。

実務でいちばん効くのは `COMP-3` を見た瞬間の反応です。

- それは packed decimal
- たぶん金額、税額、件数、レート系
- テキストとして見ると壊れて見えて当然
- CSV や UTF-8 の気分で眺めると事故る

という理解を持っておくと、ダンプやバイナリファイルの見え方で無駄に panic しにくくなります。

もう 1 つだけ補足すると、`DISPLAY` だからといって必ず ASCII 文字列とは限りません。  
z/OS 系では EBCDIC が前提になるため、**数字が文字で見えていても、バイト値は ASCII の `'0'` - `'9'` とは違う** ことがあります。[^ebcdic]

### 5.4 REDEFINES / OCCURS / COPY / FILLER

この 4 つは、読むときの詰まりどころです。

#### REDEFINES

`REDEFINES` は、**同じ領域を別の形で見る** 仕組みです。コピーではありません。[^redefines]

```cobol
       01  REC-BUF.
           05  REC-TYPE      PIC X.
           05  REC-DATA      PIC X(99).

       01  HEADER-REC REDEFINES REC-BUF.
           05  HDR-TYPE      PIC X.
           05  HDR-DATE      PIC 9(8).
           05  FILLER        PIC X(91).
```

これは C 系でいう `union` 的な感覚に近いです。  
**「1 つの 100 バイトを、別レコード種別として見分ける」** みたいな書き方でよく出ます。

#### OCCURS

`OCCURS` は配列です。COBOL では table と呼ばれがちです。

```cobol
       05  WS-ITEM OCCURS 12 TIMES.
           10  WS-PRICE    PIC 9(5).
```

さらに `OCCURS DEPENDING ON` が出たら、**可変長テーブル** です。  
この場合、後続項目の位置まで影響することがあるので、固定長の気分で追うと足を踏み外します。[^odo]

#### COPY

`COPY` は compile time の include です。  
つまり、いま開いているソースは **まだ完成形ではない** 可能性があります。[^copy]

```cobol
       COPY CUSTOMER-REC.
       COPY ERROR-MAP.
```

レコード定義、共通フラグ、SQL 用の host variable、外部インターフェースが copybook に押し込まれているのはかなり普通です。

`COPY` が多くて読みにくいときは、**展開後ソースや compiler listing を見られないか** を確認したほうが早いです。IBM Enterprise COBOL には `MDECK` という、ライブラリ処理後の入力ソースを書き出すための option もあります。[^mdeck]

#### FILLER

`FILLER` は名前のない項目です。  
ただし、「参照しないから無意味」ではありません。

- 予約領域
- 旧仕様との互換用の穴
- レコード長合わせ
- `REDEFINES` 用の余白

として普通に効きます。

**FILLER は名前がないだけで、バイト数としては存在する**。  
これを忘れると、外部ファイルとのマッピングで 1 バイトずつ世界がずれていきます。

## 6. PROCEDURE DIVISION の最低限

`DATA DIVISION` が地図なら、`PROCEDURE DIVISION` は移動経路です。

### 6.1 PERFORM

`PERFORM` は COBOL の基本的な制御移動です。  
ざっくり言うと、**処理を呼んで戻る** です。[^perform]

よく見る形は次です。

```cobol
       PERFORM INIT-PROC
       PERFORM UNTIL EOF
           PERFORM READ-PROC
           IF NOT EOF
               PERFORM EDIT-PROC
               PERFORM WRITE-PROC
           END-IF
       END-PERFORM
```

`PERFORM` には大きく 2 系統あります。

- 段落や節を指定する out-of-line `PERFORM`
- その場にブロックを書く inline `PERFORM ... END-PERFORM`

さらに古いコードでは `PERFORM A-100 THRU A-199` のような **範囲指定** も普通に出ます。  
これは便利ですが、段落を途中で足すと巻き込み事故が起きやすいので、読むときは範囲の終端をちゃんと見ます。

### 6.2 IF / EVALUATE / スコープ

条件分岐は `IF` が基本です。  
`EVALUATE` は `switch/case` 的なものだと思えばだいたい合っています。

気を付けるべきなのは **スコープの終わり方** です。[^scope]

- `END-IF`
- `END-PERFORM`
- `END-READ`

のような **明示的な終端** があるコードはまだ読みやすいです。

問題は古いコードです。COBOL では `.` が **暗黙の scope terminator** として働き、まだ閉じていない文をまとめて終わらせます。[^scope]

つまり、たった 1 個のピリオドで、

- どこまでが `IF` か
- どこまでが `PERFORM` か
- どこで次の sentence に移るか

が変わります。

さらに `NEXT SENTENCE` は `CONTINUE` と同じではありません。  
`NEXT SENTENCE` は **次のピリオドの後ろへ進む** ので、後続の `.` の位置次第で飛び先が変わります。[^scope]

古い COBOL を読むときは、**行末ではなくピリオドを見る** くらいでちょうどいいです。

### 6.3 READ / WRITE / CALL

業務 COBOL で頻出なのはこのへんです。

- `READ`
- `WRITE`
- `REWRITE`
- `START`
- `CALL`

特に `READ ... AT END ...` は王道です。

```cobol
       READ IN-FILE
           AT END
               SET EOF TO TRUE
           NOT AT END
               PERFORM PROCESS-REC
       END-READ
```

`CALL 'SUBPGM' USING ...` があれば、別プログラムへ飛びます。  
そのときは、呼ばれ先の `LINKAGE SECTION` と `PROCEDURE DIVISION USING` を見ると、受け渡しの形がかなり見えます。

## 7. COBOL の外側にあるもの

COBOL は、ソースだけで世界が完結していないことがかなりあります。

- ファイル定義
- 実行環境
- DB 接続
- トランザクション環境
- job 制御

が外側に分かれているからです。

最低限、次は押さえると読みやすくなります。

### ファイルと `FILE STATUS`

`ENVIRONMENT DIVISION` の `FILE-CONTROL` と、`DATA DIVISION` の `FILE SECTION` / `FD` はセットで読みます。[^file-fd]

```cobol
       SELECT IN-FILE ASSIGN TO ...
           FILE STATUS IS WS-FS.

       FD  IN-FILE.
       01  IN-REC.
           05 ...
```

`FILE STATUS` があれば、各 I/O 後の結果コードが入ります。  
ファイル系の障害や EOF 判定を読むときは、これを見ないと始まりません。[^file-status]

### `EXEC SQL`

これが出たら、埋め込み SQL です。

```cobol
       EXEC SQL
           SELECT ...
       END-EXEC.
```

この場合、COBOL は「ホスト変数の器」で、実際の取得条件や更新対象は SQL 側にあります。  
なので、**`EXEC SQL` の中身を普通の SQL として読む** のが近道です。

### `EXEC CICS`

これが出たら、CICS のトランザクション文脈です。[^cics]

```cobol
       EXEC CICS
           RECEIVE MAP(...)
       END-EXEC.
```

この瞬間、単なるバッチ読解ではなくなります。  
画面、トランザクション、応答コード、COMMAREA など、外部文脈込みで読む必要があります。

### JCL や実行定義

mainframe batch では、**実際にどのデータセットが割り当てられるか** や **どの順で job が流れるか** が COBOL ソースの外にあることも珍しくありません。  
ソースだけ見て「このファイルはどこにあるのか」が分からないときは、コードが悪いのではなく、見ている範囲がまだ足りていないだけ、ということが普通にあります。

## 8. 最低限の読み順

突然 COBOL を読むことになったときは、次の順番が安全です。

1. **`COPY` を全部洗う**  
   copybook を開けるなら開く。無理なら listing や展開後ソースを探す
2. **`01` レベルのレコード定義を拾う**  
   `FILE SECTION`、`WORKING-STORAGE`、`LINKAGE SECTION` の最上位を一覧化する
3. **`PIC` と `USAGE` を読む**  
   金額、日付、件数、コード、フラグを識別する
4. **`READ` / `WRITE` / `REWRITE` / `CALL` / `EXEC SQL` / `EXEC CICS` を検索する**  
   入出力と外部境界を先に掴む
5. **最初の主経路だけ追う**  
   `PROCEDURE DIVISION` の先頭から `PERFORM` 連鎖をなぞる
6. **`88` と status 項目を見る**  
   EOF、正常/異常、種別コードの意味が読みやすくなる
7. **`REDEFINES` / `OCCURS DEPENDING ON` / `COMP-3` に印を付ける**  
   後で必ず効くので、先に危険物としてマークしておく
8. **ファイルなら `FILE STATUS` を見る**  
   I/O エラー系の読み違いをかなり減らせる

この順番だと、いきなり全文を精読しなくて済みます。  
COBOL は、最初から 100% 理解しようとするより、**レコード、外部境界、主経路** の 3 点を押さえてから細部へ行くほうがずっと楽です。

## 9. よくある詰まりどころ

最後に、初心者がかなり高確率で引っかかる場所をまとめます。

### `REDEFINES` を「別の変数」だと思う

違います。  
同じ領域を別の形で読んでいます。片方を書き換えると、もう片方の見え方も変わります。[^redefines]

### `88` を「独立した bool」だと思う

違います。  
直前項目の値に名前が付いているだけです。`SET WS-OK TO TRUE` は、裏では基底項目へ対応値を入れます。[^cond88]

### `COPY` を無視して本文だけ読む

それは地図の半分を畳んだまま山に入る行為です。  
フィールド定義、共通フラグ、host variable がごっそり外にあることは普通です。[^copy]

### `MOVE` を単純代入だと思う

`MOVE` は単なる `memcpy` ではありません。  
受け側の型に応じて、変換、桁合わせ、ゼロ埋め、切り詰め、編集・逆編集が入ることがあります。[^move]

### `.` の影響を軽く見る

COBOL の `.` は想像より重いです。  
明示終端がない古いコードでは、**このピリオドがどこまで閉じているか** を見誤ると制御フローを読み違えます。[^scope]

### packed decimal や EBCDIC を「文字化け」だと思う

壊れているとは限りません。  
最初から文字列ではない、または ASCII ではないだけ、ということがかなりあります。[^numeric-repr][^ebcdic]

### `OCCURS DEPENDING ON` の後ろを固定位置だと思う

可変長テーブルの後続項目は、値によって位置が動くことがあります。  
固定長の頭で読むと、オフセット計算が全部ずれます。[^odo]

## 10. まず見る早見表

| 見つけた語 | まず考えること |
|---|---|
| `01` | レコードやグループの最上位。ここから全体像を掴む |
| `88` | フラグや状態コードの意味名。分岐を読む鍵 |
| `PIC X(...)` | 文字項目 |
| `PIC 9(...)` / `S9(...)V...` | 数値項目。桁数と小数位置を確認 |
| `COMP` | binary |
| `COMP-3` | packed decimal。金額・件数の可能性が高い |
| `REDEFINES` | 同じ領域を別解釈している |
| `OCCURS` | 配列・table |
| `OCCURS DEPENDING ON` | 可変長。後続位置にも注意 |
| `FILLER` | 名前はないが長さはある |
| `COPY` | copybook を見ないと完成形が見えない |
| `PERFORM` | 主経路の骨格 |
| `READ` / `WRITE` / `REWRITE` | ファイル I/O |
| `EXEC SQL` | DB 処理 |
| `EXEC CICS` | トランザクション処理 |
| `FILE STATUS` | I/O の結果コード |

## 11. まとめ

COBOL は、古いから難しいのではありません。  
**データ定義、外部ファイル、実行文脈が密に結び付いている** ので、最初の入口が見えにくいだけです。

読むための最小セットをもう一度まとめると、こうです。

- `DIVISION` で地図を掴む
- `DATA DIVISION` を先に読む
- `PIC` と `USAGE` で項目の形を読む
- `COMP-3`、`REDEFINES`、`OCCURS`、`88`、`COPY` に印を付ける
- `PERFORM`、`READ`、`WRITE`、`CALL` を追う
- `FILE STATUS`、`EXEC SQL`、`EXEC CICS` で外部境界を押さえる
- `.` の効き方を甘く見ない

ここが見えると、COBOL は「謎の古代魔法」から「レコード処理の言語」へ変わります。  
レガシー技術は、名前が古いから怖いのではなく、**最初に見る縮尺を間違えると急に分かりにくい** だけです。地図の縮尺が合えば、意外と普通に読めます。

## 12. 参考資料

本文中の主な参照先です。

[^ref-format]: IBM, “Reference format” https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=structure-reference-format / IBM, “Area A or Area B” https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=format-area-area-b / Micro Focus, “Fixed Format” https://www.microfocus.com/documentation/visual-cobol/vc60/DevHub/HRLHLHINTR01U904.html
[^level-numbers]: IBM, “Level-numbers” https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=entry-level-numbers
[^cond88]: IBM, “Format 2: condition-name value” https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=vc-format-2
[^numeric-repr]: IBM, “Examples: numeric data and internal representation” https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=data-examples-numeric-internal-representation
[^comp3]: IBM, “PACKED-DECIMAL (COMP-3)” https://www.ibm.com/docs/ja/cobol-zos/6.4.0?topic=v6-packed-decimal-comp-3
[^redefines]: IBM, “REDEFINES 節” https://www.ibm.com/docs/ja/cobol-zos/6.4.0?topic=entry-redefines-clause
[^odo]: IBM, “OCCURS DEPENDING ON clause” https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=clause-occurs-depending
[^perform]: IBM, “PERFORM statement” https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=statements-perform-statement / IBM, “Procedure division structure” https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=division-procedure-structure
[^file-fd]: IBM, “ファイル構造の詳細記述” https://www.ibm.com/docs/ja/cobol-linux-x86/1.2.0?topic=files-describing-structure-file-in-detail
[^copy]: IBM, “COPY ステートメント” https://www.ibm.com/docs/ja/cobol-linux-x86/1.2.0?topic=statements-copy-statement
[^mdeck]: IBM, “Enterprise COBOL compiler options” https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=guide-enterprise-cobol-compiler-options
[^ebcdic]: IBM, “The EBCDIC character set” https://www.ibm.com/docs/en/zos-basic-skills?topic=mainframe-ebcdic-character-set / IBM, “Handling differences in ASCII SBCS and EBCDIC SBCS characters” https://www.ibm.com/docs/en/cobol-linux-x86/1.2.0?topic=fdcbdr-handling-differences-in-ascii-sbcs-ebcdic-sbcs-characters
[^file-status]: IBM, “FILE STATUS clause” https://www.ibm.com/docs/en/cobol-linux-x86/1.2.0?topic=section-file-status-clause / IBM, “Using file status keys” https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=operations-using-file-status-keys
[^scope]: IBM, “Scope terminators” https://www.ibm.com/docs/en/cobol-aix/5.1.0?topic=division-scope-terminators / IBM, “Coding a choice of actions” https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=actions-coding-choice
[^move]: IBM, “Elementary move rules” https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=moves-elementary-move-rules
[^cics]: IBM, “CICS のもとで実行する COBOL プログラムのコーディング” https://www.ibm.com/docs/ja/cobol-zos/6.3.0?topic=cics-coding-cobol-programs-run-under
