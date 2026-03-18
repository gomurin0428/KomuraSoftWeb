# 共有メモリを使うときの落とし穴とベストプラクティス - 同期、可視性、寿命、ABI、セキュリティを先に整理

画像フレーム、検査結果、時系列ログ、板情報、巨大バッファ。  
同一マシン内で大きなデータを低レイテンシでやり取りしたいとき、共有メモリはかなり魅力的です。

ただし、ここで少し危ないのは、共有メモリが **「速い IPC」** という顔で近づいてくることです。  
実際には、共有メモリは **「コピーを減らせる代わりに、整合性の責任をアプリ側へ押し返してくる IPC」** です。

- 速い
- 柔軟
- でも protocol は自前
- 事故ると症状が派手

だいたいこの 4 点セットです。

この記事では、Windows の file mapping と POSIX `shm_open` / `mmap` を念頭に、**共有メモリを実務で使うときの詰まりどころと、事故率を下げる設計** を整理します。  
C/C++ でも C# の `MemoryMappedFile` でも、本質はほぼ同じです。[^dotnet-mmf]

## 目次

1. まず結論（ひとことで）
2. 共有メモリは何を共有して、何を共有しないのか
3. 共有メモリが向いている場面 / 向いていない場面
4. 最初に決めるべき 4 つのこと
5. よくある落とし穴
   - 5.1 同期しない
   - 5.2 `volatile` で何とかしようとする
   - 5.3 途中状態を読ませる
   - 5.4 ポインタや複雑オブジェクトをそのまま置く
   - 5.5 ABI が壊れる
   - 5.6 初期化レース
   - 5.7 クラッシュ復旧を考えない
   - 5.8 false sharing とキャッシュライン競合
   - 5.9 名前・権限・セキュリティを軽く見る
   - 5.10 サイズ変更とアップグレードを雑にやる
   - 5.11 通知まで全部 shared memory に押し込む
   - 5.12 「これで他マシンとも共有できる」と思う
6. ベストプラクティス
   - 6.1 control plane と data plane を分ける
   - 6.2 先頭に固定ヘッダを置く
   - 6.3 オフセット参照にする
   - 6.4 並行モデルを絞る
   - 6.5 commit protocol を明示する
   - 6.6 サイズは世代ごとに固定する
   - 6.7 観測可能性を入れる
   - 6.8 異常系テストを先に作る
7. Windows と POSIX で見るポイント
8. まず見るチェックリスト
9. まとめ
10. 参考資料

* * *

## 1. まず結論（ひとことで）

先にかなり雑に、でも実務で役に立つ言い方をすると、こうです。

- 共有メモリは **同じバイト列** を複数プロセスから見せる仕組みであって、**同期そのもの** ではありません[^win-share][^posix-shm]
- **速いのは大きなデータ** を同一マシン内でやり取りするときです。小さい制御メッセージだけなら、pipe / socket / named pipe / queue のほうが楽なことがかなり多いです
- 共有メモリでは、**見えること** と **安全に読めること** が別問題です
- `volatile` は設計の土台にしないほうがよいです。**原子性、順序、待機** は別に考えます[^msvc-volatile][^win-interlocked]
- **生ポインタ、`HANDLE`、file descriptor、`std::string`、`std::vector`、`std::mutex`** をそのまま置くと、だいたい後で泣きます
- 共有メモリに置くデータは、**固定幅整数 + 明示的レイアウト + バージョン付きヘッダ** に寄せたほうが安全です
- **先頭ヘッダに magic / version / size / state / generation / heartbeat** を置くだけで、事故調査のしやすさがかなり変わります
- 共有メモリの難所は速度ではなく、**初期化、寿命、復旧、権限、ABI** です
- Windows なら **`CreateFileMapping` / `OpenFileMapping` / `MapViewOfFile`**、POSIX なら **`shm_open` / `ftruncate` / `mmap`** が骨格です[^win-named][^posix-shm]
- 一番事故りにくいのは、**SPSC（single-producer single-consumer）のリングバッファ** か、**ダブルバッファ** から始めることです

要するに、**共有メモリは速いけれど、雑に使うと「勝手に同期されている気がする病」にかかる**。ここを避けるのが最初の勝負です。

## 2. 共有メモリは何を共有して、何を共有しないのか

共有メモリは、ざっくり言うと **同じ物理ページ** を複数プロセスの仮想アドレス空間へマップする仕組みです。  
Windows では file mapping object と view を使い、POSIX では shared memory object を `mmap` します。[^win-share][^win-scope][^posix-shm]

ここで大事なのは 2 点です。

1. **共有されるのは中身のバイト列であって、仮想アドレスそのものではない**
2. **coherent であること** と **同期されていること** は別

Windows のドキュメントでも、同じ file mapping object から作った view は同時点で coherent だとされています。  
ただし、それは **読者が常に一貫した更新済みレコードを読める** という意味ではありません。[^win-createfilemapping]

たとえば、

- writer が `length`
- つづいて `payload`
- つづいて `ready flag`

の順に書くつもりでも、reader 側が何の同期もなく読むと、**新しい `length` と古い `payload`** を組み合わせて見ることがあります。  
共有メモリはここを自動では直してくれません。

つまり、共有メモリが共有するのは **バイト**。  
共有しないのは **意味、順序、完了通知、復旧方針** です。  
このへんは全部、こちらで設計する必要があります。

## 3. 共有メモリが向いている場面 / 向いていない場面

| 場面 | 向き・不向き | 理由 |
|---|---|---|
| 同一マシン内で大きなフレームやバッファを渡す | 向いている | コピー回数を減らしやすい |
| 高頻度のセンサ値、画像、音声、板情報など | 向いている | 低レイテンシ・高スループットを狙いやすい |
| 小さいコマンドや応答だけをやり取りする | あまり向かない | 制御のための同期コストが相対的に重い |
| 他マシンとやり取りする | 向かない | 共有メモリは基本的に同一ホスト前提 |
| 異なる言語・異なるバージョンが長期共存する | 難しい | ABI とバージョニング設計が必要 |
| 永続化も必要 | 目的次第 | file-backed mapping は有力だが、永続化と IPC の責務が混ざりやすい |

実務では、**制御はメッセージ系、データ本体は共有メモリ** という分離がかなり強いです。  
たとえば、

- UI プロセス → worker プロセスへ「次のフレームを使え」と通知するのは event / pipe / socket
- 実際のフレーム本体は共有メモリ

という構成です。  
これがわりと平和です。

## 4. 最初に決めるべき 4 つのこと

共有メモリを設計するとき、最初に決めるべきなのは次の 4 つです。

### 4.1 control plane と data plane を分ける

何を shared memory に置くのかを先に決めます。

- **data plane**: 画像、音声、レコード列、バルクデータ
- **control plane**: 開始、停止、エラー、再接続、再初期化、通知

この 2 つを分けるだけで、shared memory 側の設計がかなり単純になります。

### 4.2 並行モデルを絞る

- SPSC: 1 producer / 1 consumer
- MPSC: 多 writer / 1 consumer
- SPMC: 1 writer / 多 reader
- MPMC: 多 writer / 多 reader

難易度は、だいたいこの順で上がります。  
最初から MPMC に行くのは、かなり勇ましいです。たいてい後でメモリ順序の妖怪が出ます。

### 4.3 所有者と寿命を決める

- 誰が作るか
- 誰が初期化するか
- 誰が消すか
- 参加者が途中で落ちたとき、誰が回復させるか

ここが曖昧だと、起動順や再起動のたびに空気が濁ります。

### 4.4 ABI とバージョンを決める

- レイアウト
- 型サイズ
- alignment
- reserved 領域
- version / feature flags
- 互換性の有無

shared memory は API ではなく **ABI（binary interface）** の話です。  
ここを雑にすると、ソース互換はあるのに実行時だけ壊れる、という嫌な事故になります。

## 5. よくある落とし穴

### 5.1 同期しない

いちばん多いのはこれです。

「同じメモリを見ているのだから、書いたら読めるだろう」

読めることはあります。  
でも、それは **正しいタイミングで、正しい単位で、正しい順序で** 読めることを意味しません。

Windows でも POSIX でも、共有メモリへのアクセスは **別の同期手段と組み合わせる前提** です。  
Windows の説明でも、共有 view へのアクセスは mutex / semaphore / event などで協調するよう書かれています。[^win-share]  
POSIX の説明でも、shared memory へのアクセスは同期が必要です。[^posix-training]

### 5.2 `volatile` で何とかしようとする

`volatile` は、共有メモリ設計を救ってくれる魔法ではありません。  
少なくとも **atomicity** と **mutual exclusion** は別問題です。[^msvc-volatile][^win-interlocked]

たとえば `volatile bool ready;` を置いて busy loop する設計は、

- CPU を無駄に使う
- payload と ready の順序保証が曖昧になる
- portable ではない
- 途中状態を拾いやすい

と、だいたい良いことがありません。

さらに Windows の `WaitOnAddress` は **同じプロセス内の thread 向け** です。  
cross-process の待機機構としては考えないほうが安全です。[^win-waitonaddress]

### 5.3 途中状態を読ませる

共有メモリで事故るときの見た目は、かなり普通です。

- ヘッダだけ新しい
- ペイロードだけ古い
- 長さだけ更新済み
- 2 つのフィールドの組が壊れている

単一の scalar を atomic に更新するだけなら話は比較的単純ですが、**複数フィールドからなるレコード** を公開するなら、commit の手順が必要です。

典型的には次のどれかです。

- mutex で丸ごと守る
- **ダブルバッファ** にして最後に「今の有効バッファ番号」を切り替える
- **リングバッファ** にして slot ごとに state / sequence を持つ
- 1 writer / 多 reader なら **sequence counter** で snapshot を取る

「最後に ready flag を立てる」だけでも、**その flag をどういうメモリ順序で書くか / 読むか** を決めないと、設計としてはまだ甘いです。  
共有メモリでは、**公開タイミングそのものがプロトコル** です。

### 5.4 ポインタや複雑オブジェクトをそのまま置く

これはかなり頻出です。

- 生ポインタ
- `HANDLE`
- file descriptor
- `std::string`
- `std::vector`
- `std::unordered_map`
- `std::mutex`
- `CRITICAL_SECTION`

このへんを shared memory にそのまま置いて、別プロセスから使おうとするやつです。だいたい小さな地獄が始まります。

理由は単純で、**仮想アドレスや process-local な資源は、その process の文脈にしか意味がない** からです。  
Windows の view も、同じ mapping を別 process で map しても、**仮想アドレスは一致するとは限りません**。[^win-scope][^win-mapviewex]

なので、参照が必要なら **ベースアドレスからの offset** で持つのが基本です。

```c
typedef struct ShmRef {
    uint64_t offset;   // セグメント先頭からの相対位置
    uint32_t length;
    uint32_t kind;
} ShmRef;
```

これなら、各 process が `base + offset` で自分のアドレスに直せます。

### 5.5 ABI が壊れる

shared memory は、ソースコードではなく **バイナリの約束** です。  
つまり、次の違いが全部効きます。

- `int` / `long` のサイズ
- `bool` の表現
- `enum` の underlying type
- `wchar_t` のサイズ
- 32bit / 64bit の差
- `#pragma pack`
- compiler / language の違い
- alignment / padding
- little-endian / big-endian

同一ホスト内なら endianness は揃っていることが多いですが、**ARM64 対応や mixed toolchain** が入るだけでも、かなり普通にずれます。

なので、shared memory に置く構造は次を強く勧めます。

- `uint32_t` / `uint64_t` などの **固定幅整数**
- 明示的な **padding / reserved**
- header に `version`, `header_size`, `record_size`, `total_size`
- 必要なら `static_assert(sizeof(...))`
- **非 trivial object を置かない**

### 5.6 初期化レース

shared memory は「作った側が初期化したはず」という思い込みで壊れやすいです。

Windows では、`CreateFileMapping` が既存名に当たると **既存オブジェクトを返し**、`GetLastError()` で `ERROR_ALREADY_EXISTS` が分かります。  
pagefile-backed な mapping の初期ページは 0 で始まります。[^win-createfilemapping]  
POSIX では、新しい shared memory object は **最初は長さ 0** で、`ftruncate` でサイズを付けます。新しく確保されたバイトは 0 初期化です。`O_CREAT | O_EXCL` による create は原子的です。[^posix-shm]

この差を知らないまま、

- open したら即使う
- 初期化完了フラグがない
- 参加者が同時に初期化する
- version mismatch を見ない

とやると、起動順次第で壊れます。

最低限、先頭ヘッダに次の state を置いたほうがよいです。

- `INITIALIZING`
- `READY`
- `BROKEN`

そして **creator だけが初期化** し、joiner は `READY` を待つ。  
この作法だけで、かなり世界が静かになります。

### 5.7 クラッシュ復旧を考えない

writer が共有データ更新中に落ちたらどうするか。  
ここを未定義のまま本番へ出すと、障害時の顔つきが急に深刻になります。

Windows の mutex は、所有 thread が release せずに終了すると **abandoned** になり、wait 側は `WAIT_ABANDONED` を受け取れます。これは **共有資源が不定状態かもしれない** という意味です。[^win-mutex]  
POSIX の robust mutex でも、owner が死んだとき `EOWNERDEAD` が返り、修復後に `pthread_mutex_consistent()` を呼ぶ流れがあります。[^posix-robust][^posix-consistent]

大事なのは、ここで「とりあえず続行」しないことです。  
復旧には少なくとも次のどれかが要ります。

- generation 番号
- 最終 commit 済み sequence
- heartbeat
- dirty / clean flag
- journal 的な 2 段 commit
- 破損時の全再初期化手順

### 5.8 false sharing とキャッシュライン競合

shared memory は速い、と言われがちです。  
でも hot なカウンタが同じ cache line に詰まっていると、CPU 間で line が行ったり来たりして、景気よく遅くなります。

典型例は、

- producer が `write_index` を更新
- consumer が `read_index` を更新
- 両方が同じ cache line に乗っている

というやつです。

この場合は、

- hot field を別 cache line に分ける
- 更新頻度の高い field と低い field を分ける
- 1 writer 1 cache line を意識する

だけでかなり変わります。  
64 bytes に揃える話がよく出ますが、**64 bytes は多くの CPU でありがちな値であって絶対法則ではない**、くらいの気持ちで見てください。

### 5.9 名前・権限・セキュリティを軽く見る

named shared memory は便利ですが、名前と権限を雑にすると事故ります。

Windows では、

- `Global\` と `Local\` の namespace がある
- session 0 以外から `Global\` の file mapping を **新規作成** するには `SeCreateGlobalPrivilege` が要る
- object name は event / semaphore / mutex / waitable timer / job と **namespace を共有** する

という癖があります。[^win-global][^win-createfilemapping][^win-share]

つまり、

- `"Global\\MyApp"` にしたら service と desktop app で共有できる気がする
- でも権限で失敗する
- しかも同名の mutex を先に作っていて `ERROR_INVALID_HANDLE` になる

みたいな、たいへん Windows らしい泥が出ます。

POSIX 側でも、`shm_open` の `mode` や `umask` を軽く見ると、不要に広く見えたり、逆に開けなかったりします。[^posix-shm]

shared memory は **ただメモリだから安全** ではありません。  
読める権限がある process からは、かなり素直に見えます。  
機密情報を置くなら、通常のメモリと同じく paging / swap / dump / 権限の文脈で考える必要があります。

### 5.10 サイズ変更とアップグレードを雑にやる

共有メモリを「あとからちょっと広げたい」は、わりと危ない要求です。

- Windows の mapping object には作成時のサイズがある[^win-createfilemapping]
- POSIX でも `ftruncate` と `mmap` の整合を考えないと、参加者側の map 長と合わなくなります[^posix-shm][^posix-mmap]

実務では、**サイズはその世代では不変** にしたほうが安全です。  
拡張が必要なら、

1. 新しい version / name / generation の segment を作る
2. 参加者を切り替える
3. 旧 segment を閉じる

のほうが事故率は下がります。

### 5.11 通知まで全部 shared memory に押し込む

よくあるのが、

- 共有メモリに `ready = 1`
- 相手は `while (!ready) Sleep(1);`

です。

これ、最初は動きます。  
でも後で、

- CPU を無駄に使う
- `Sleep(1)` でレイテンシが揺れる
- 取りこぼしに気づきにくい
- タイムアウトや終了通知がきれいに書きづらい

という形で返ってきます。

共有メモリは **データ面** に寄せ、通知は **待てる primitive** へ逃がしたほうがよいです。

- Windows: event / semaphore / mutex / named pipe など[^win-share][^win-usemutex]
- POSIX: semaphore / process-shared mutex + condvar など[^posix-sem][^posix-pshared-cond]

### 5.12 「これで他マシンとも共有できる」と思う

file-backed mapping を使ってネットワーク越しの共有ファイルを map すれば、他マシンとも shared memory 的にいけるのでは、と思いたくなる瞬間があります。

ここは危ないです。

Windows の `CreateFileMapping` の説明でも、**remote file に対しては coherence が保証されない** とされています。  
同じページを 2 台が writable に map した場合、それぞれ自分の書き込みしか見えず、ディスク更新時に merge もされません。[^win-createfilemapping]

共有メモリは、基本的に **同一ホスト内** の仕組みです。  
マシンをまたぐなら、素直に socket / RPC / message broker を選んだほうが正気を保ちやすいです。

## 6. ベストプラクティス

### 6.1 control plane と data plane を分ける

shared memory には **バルクデータだけ** を置き、通知と状態遷移は別チャンネルへ逃がします。

- shared memory: frame, sample, batch, snapshot
- event / semaphore / pipe / socket: ready, consumed, stop, error, reconnect

この分離は、性能より先に **設計の見通し** を良くします。

### 6.2 先頭に固定ヘッダを置く

最低限、先頭にこういうヘッダを置くことを強く勧めます。

```c
typedef struct SharedHeader {
    uint32_t magic;
    uint16_t abi_version;
    uint16_t header_size;

    uint32_t state;          // 0=initializing, 1=ready, 2=broken
    uint32_t flags;

    uint64_t total_size;
    uint64_t generation;
    uint64_t heartbeat_ns;

    uint64_t payload_offset;
    uint64_t payload_size;

    uint64_t write_seq;
    uint64_t read_seq;

    uint8_t  reserved[64];
} SharedHeader;
```

ポイントは、

- `magic` で別物や未初期化を弾く
- `abi_version` と `header_size` で layout 差異を弾く
- `state` で初期化途中を弾く
- `generation` で再作成を検知する
- `heartbeat` で死活を見る
- `reserved` で将来拡張の逃げ道を作る

です。

shared memory で辛いのは、「何が起きているか見えにくい」ことです。  
だからこそ、**観測用の metadata** を最初から持たせます。

### 6.3 オフセット参照にする

参照は pointer ではなく **offset** で持ちます。

- `base + offset` で解決する
- `offset + length` の範囲チェックを入れる
- invalid value 用の sentinel を決める

これだけで、address mismatch 系の事故がかなり減ります。

### 6.4 並行モデルを絞る

shared memory は、writer が増えると急に難しくなります。  
なので、最初はこのどちらかが強いです。

- **SPSC ring buffer**
- **1 writer / 多 reader の snapshot**

多 writer が必要なら、

- enqueue だけは lock-free / atomic
- 実データ更新は consumer 1 つへ集約

のように、**整合性の責任点を減らす** ほうがだいたいうまくいきます。

### 6.5 commit protocol を明示する

「どの瞬間から読んでよいか」を文章で説明できない設計は危ないです。

たとえばダブルバッファなら、

1. 非公開側バッファへ書く
2. チェックサムや長さを確定する
3. release 付きで active buffer index を切り替える
4. reader は acquire 付きで active index を読む
5. 読み終えたら index が変わっていないか確認する

のように、**公開の儀式** を決めます。

### 6.6 サイズは世代ごとに固定する

resize in place より、

- `name = MyShm.v3`
- `abi_version = 3`
- `generation = 42`

のように世代を切ったほうが保守しやすいです。

共有メモリは API のように「呼び出し時に型チェック」してくれません。  
だから **一度決めた ABI をこわさない** ことが重要です。

### 6.7 観測可能性を入れる

最低限あると助かるのは次です。

- 最終更新時刻
- 最終成功 sequence
- drop 数 / overwrite 数
- version mismatch 数
- attach / detach 数
- last error code
- heartbeat

shared memory が壊れるときは、だいたいログが薄いです。  
自前で counters を置くと、障害対応がかなり楽になります。

### 6.8 異常系テストを先に作る

正常系だけでは足りません。少なくとも次は見たほうがいいです。

- writer 更新中に強制終了
- reader 遅延で ring があふれる
- version mismatch で接続
- 32bit / 64bit 混在
- session をまたいだ open
- 権限不足
- 先行プロセスが古い世代を持ったまま再起動
- huge data 連続転送時の cache miss / NUMA 影響

shared memory は正常系より **壊し方テスト** のほうが価値が大きいです。

## 7. Windows と POSIX で見るポイント

| 観点 | Windows | POSIX |
|---|---|---|
| 作成 / open | `CreateFileMapping` / `OpenFileMapping` / `MapViewOfFile`[^win-named] | `shm_open` / `ftruncate` / `mmap`[^posix-shm] |
| ディスク非連携の共有 | `INVALID_HANDLE_VALUE` を指定した pagefile-backed mapping[^win-named][^win-createfilemapping] | POSIX shared memory object + `mmap`[^posix-shm] |
| 初期値 | pagefile-backed pages は 0 初期化[^win-createfilemapping] | 新規 object は長さ 0。新規確保バイトは 0 初期化[^posix-shm] |
| 同期 | mutex / semaphore / event / interlocked など[^win-share][^win-interlocked] | process-shared mutex / condvar / semaphore[^posix-pshared][^posix-sem] |
| cross-process で使ってはいけないもの | `CRITICAL_SECTION`, `WaitOnAddress`[^win-cs][^win-waitonaddress] | `PTHREAD_PROCESS_PRIVATE` のままの mutex / condvar[^posix-pshared][^posix-pshared-cond] |
| owner death | `WAIT_ABANDONED`[^win-mutex] | robust mutex + `EOWNERDEAD` / `pthread_mutex_consistent()`[^posix-robust][^posix-consistent] |
| name の削除 | 最終 handle / view 解放で消える[^win-share][^win-createfilemapping] | `shm_unlink` で名前削除。参照が残っていれば実体は最後まで残る[^posix-unlink][^posix-shm-unlink] |
| namespace / 権限 | `Global\` / `Local\`、ACL、`SeCreateGlobalPrivilege`[^win-global][^win-security] | `mode`, `umask`, 名前空間、`O_CREAT|O_EXCL`[^posix-shm] |

C# の `MemoryMappedFile` も、本質的には Windows の file mapping のラッパです。  
だから、

- 同じ名前で open する
- 別途 mutex / event を使う
- ビューに対して明示レイアウトで読む
- オブジェクト参照をそのまま置かない

という基本は変わりません。[^dotnet-mmf]

## 8. まず見るチェックリスト

- 本当に共有メモリが要るか。**同一ホストで大きなデータ** か
- control plane と data plane を分けたか
- 並行モデルは **SPSC / 1 writer 多 reader** まで落とせないか
- 先頭ヘッダに **magic / version / size / state / generation / heartbeat** があるか
- pointer / `HANDLE` / fd / STL object / `std::mutex` を置いていないか
- reader が途中状態を見ない **commit protocol** があるか
- 初期化者が 1 人に定まっているか
- 異常終了時の **復旧手順** があるか
- 名前と権限を明示しているか
- `Global\` が本当に必要か
- resize in place を前提にしていないか
- writer kill / reader stall / version mismatch / 権限不足を試したか

## 9. まとめ

共有メモリは、うまく使えばかなり強いです。  
特に、

- 画像
- 音声
- センサ列
- 大きなバッチ
- 高頻度 snapshot

のような **同一マシン内の大きなデータ** では、本当に効きます。

ただし、共有メモリの本体は「速さ」より **責任の移動** です。  
コピーやカーネル越しのメッセージングを減らす代わりに、

- 同期
- 可視性
- 初期化
- ABI
- 復旧
- 権限
- 観測可能性

をこちらで引き受けることになります。

なので、最初の 1 本目はこうするのが安全です。

- **SPSC ring buffer かダブルバッファ**
- **先頭固定ヘッダ**
- **offset 参照**
- **別チャネルで通知**
- **version / generation / heartbeat あり**
- **異常系テストあり**

この形から始めると、shared memory はかなり素直な道具になります。  
逆に、いきなり「何でも置ける速い共通メモリ」として扱うと、だんだんアプリではなく考古学になります。

## 10. 参考資料

- Windows: file mapping と named shared memory の基本[^win-named][^win-createfilemapping][^win-share]
- Windows: namespace / security / synchronization[^win-global][^win-security][^win-interlocked][^win-mutex]
- POSIX: `shm_open`, `shm_unlink`, `mmap`, process-shared / robust synchronization[^posix-shm][^posix-unlink][^posix-mmap][^posix-pshared][^posix-robust]
- .NET: `MemoryMappedFile` の概要[^dotnet-mmf]

[^dotnet-mmf]: Microsoft Learn, “メモリ マップト ファイル” https://learn.microsoft.com/ja-jp/dotnet/standard/io/memory-mapped-files / Microsoft Learn, “MemoryMappedFile クラス” https://learn.microsoft.com/ja-jp/dotnet/api/system.io.memorymappedfiles.memorymappedfile?view=net-10.0
[^win-share]: Microsoft Learn, “Sharing Files and Memory” https://learn.microsoft.com/en-us/windows/win32/memory/sharing-files-and-memory
[^win-scope]: Microsoft Learn, “Scope of Allocated Memory” https://learn.microsoft.com/en-us/windows/win32/memory/scope-of-allocated-memory
[^win-named]: Microsoft Learn, “Creating Named Shared Memory” https://learn.microsoft.com/en-us/windows/win32/memory/creating-named-shared-memory / Microsoft Learn, “名前付き共有メモリの作成” https://learn.microsoft.com/ja-jp/windows/win32/memory/creating-named-shared-memory
[^win-createfilemapping]: Microsoft Learn, “CreateFileMappingA function” https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createfilemappinga
[^win-mapviewex]: Microsoft Learn, “MapViewOfFileEx function” https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-mapviewoffileex / Microsoft Learn, “MapViewOfFile function” https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-mapviewoffile
[^win-cs]: Microsoft Learn, “Critical Section Objects” https://learn.microsoft.com/en-us/windows/win32/sync/critical-section-objects
[^win-waitonaddress]: Microsoft Learn, “WaitOnAddress function” https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitonaddress
[^win-global]: Microsoft Learn, “Kernel object namespaces” https://learn.microsoft.com/en-us/windows/win32/termserv/kernel-object-namespaces
[^win-security]: Microsoft Learn, “ファイル マッピングのセキュリティとアクセス権” https://learn.microsoft.com/ja-jp/windows/win32/memory/file-mapping-security-and-access-rights / Microsoft Learn, “File Mapping Security and Access Rights” https://learn.microsoft.com/en-us/windows/win32/memory/file-mapping-security-and-access-rights
[^win-usemutex]: Microsoft Learn, “Using Mutex Objects” https://learn.microsoft.com/en-us/windows/win32/sync/using-mutex-objects
[^win-mutex]: Microsoft Learn, “Mutex Objects” https://learn.microsoft.com/en-us/windows/win32/sync/mutex-objects
[^win-interlocked]: Microsoft Learn, “Interlocked Variable Access” https://learn.microsoft.com/en-us/windows/win32/sync/interlocked-variable-access / Microsoft Learn, “MemoryBarrier function” https://learn.microsoft.com/en-us/windows/win32/api/winnt/nf-winnt-memorybarrier
[^msvc-volatile]: Microsoft Learn, “/volatile (volatile Keyword Interpretation)” https://learn.microsoft.com/en-us/cpp/build/reference/volatile-volatile-keyword-interpretation?view=msvc-170 / Microsoft Learn, “volatile (C++)” https://learn.microsoft.com/en-us/cpp/cpp/volatile-cpp?view=msvc-170
[^posix-shm]: man7.org, “shm_open(3)” https://man7.org/linux/man-pages/man3/shm_open.3.html
[^posix-unlink]: man7.org, “shm_unlink(3p)” https://man7.org/linux/man-pages/man3/shm_unlink.3p.html
[^posix-shm-unlink]: man7.org, “shm_open(3)” (shm_unlink semantics) https://man7.org/linux/man-pages/man3/shm_open.3.html
[^posix-mmap]: man7.org, “mmap(2)” https://man7.org/linux/man-pages/man2/mmap.2.html
[^posix-pshared]: man7.org, “pthread_mutexattr_getpshared(3)” https://man7.org/linux/man-pages/man3/pthread_mutexattr_getpshared.3.html / man7.org, “pthread_mutexattr_getpshared(3p)” https://man7.org/linux/man-pages/man3/pthread_mutexattr_getpshared.3p.html
[^posix-pshared-cond]: man7.org, “pthread_condattr_setpshared(3p)” https://man7.org/linux/man-pages/man3/pthread_condattr_setpshared.3p.html / man7.org, “pthread_condattr_getpshared(3p)” https://man7.org/linux/man-pages/man3/pthread_condattr_getpshared.3p.html
[^posix-sem]: man7.org, “sem_init(3)” https://man7.org/linux/man-pages/man3/sem_init.3.html / man7.org, “sem_init(3p)” https://man7.org/linux/man-pages/man3/sem_init.3p.html
[^posix-robust]: man7.org, “pthread_mutex_lock(3p)” https://man7.org/linux/man-pages/man3/pthread_mutex_lock.3p.html / man7.org, “pthread_mutexattr_setrobust(3)” https://man7.org/linux/man-pages/man3/pthread_mutexattr_setrobust.3.html
[^posix-consistent]: man7.org, “pthread_mutex_consistent(3)” https://man7.org/linux/man-pages/man3/pthread_mutex_consistent.3.html / man7.org, “pthread_mutex_consistent(3p)” https://man7.org/linux/man-pages/man3/pthread_mutex_consistent.3p.html
[^posix-training]: man7.org, “POSIX Shared Memory” training slides https://man7.org/training/download/ipc_pshm_slides-mkerrisk-man7.org.pdf
