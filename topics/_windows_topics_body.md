<div class="topic-hub-grid">
  <section class="topic-hub-card" aria-labelledby="topic-com">
    <h3 id="topic-com">COM / ActiveX / OCX と既存資産移行</h3>
    <p>Windows の既存資産をどう残し、どう包み、どこから置き換えるかを考えるトピックです。用語整理から移行判断、スレッド境界までをまとめて辿れます。</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">ActiveX / OCX を今後どう扱うべきか迷っている</div>
      <div class="topic-hub-point">COM の用語や STA / MTA が混ざって議論しにくい</div>
      <div class="topic-hub-point">全面リライトではなく段階移行の現実解を探したい</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連記事</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/blog/2026/03/13/000-what-is-com-activex-ocx/">COM / ActiveX / OCX とは何か - 違いと関係をまとめて解説</a>
        <a class="topic-hub-link" href="/blog/2026/03/12/001-activex-ocx-keep-wrap-replace-decision-table/">ActiveX / OCX を今どう扱うか - 残す・包む・置き換える判断表</a>
        <a class="topic-hub-link" href="/blog/2026/01/31/000-sta-mta-com-relationship/">COM STA/MTA の基礎知識 - スレッドモデルとハングを避ける考え方</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連ページ</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/topics/activex-migration/">ActiveX / 移行テーマ</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/legacy-asset-migration/">既存資産活用・移行支援</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/technical-consulting/">技術相談・設計レビュー</a>
      </div>
    </div>
  </section>

  <section class="topic-hub-card" aria-labelledby="topic-dotnet">
    <h3 id="topic-dotnet">.NET / Generic Host / アプリ設計</h3>
    <p>.NET アプリを少し大きく作るときに出てくる、DI、設定、ログ、起動処理、常駐処理の設計を辿るトピックです。Generic Host を起点に、アプリ全体の組み立て方を整理できます。</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">`Main` や `Program.cs` に処理が集まりすぎている</div>
      <div class="topic-hub-point">BackgroundService や常駐処理の置き場所に迷っている</div>
      <div class="topic-hub-point">DI、設定、ログを自然につなげたい</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連記事</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/blog/2026/03/14/000-dotnet-generic-host-what-is/">.NET の Generic Host とは何か - DI、設定、ログ、BackgroundService を先に整理</a>
        <a class="topic-hub-link" href="/blog/2026/03/12/002-generic-host-backgroundservice-desktop-app/">Generic Host / BackgroundService をデスクトップアプリに持ち込む理由 - 起動・寿命・graceful shutdown の整理がかなり楽になる</a>
        <a class="topic-hub-link" href="/blog/2026/03/09/001-csharp-async-await-best-practices/">C# async/await のベストプラクティス - Task.Run と ConfigureAwait の判断表</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連ページ</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/topics/generic-host-app-architecture/">Generic Host / アプリ設計テーマ</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/windows-app-development/">Windowsアプリ開発</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/technical-consulting/">技術相談・設計レビュー</a>
      </div>
    </div>
  </section>

  <section class="topic-hub-card" aria-labelledby="topic-ui">
    <h3 id="topic-ui">WPF / WinForms / UI スレッドと定期処理</h3>
    <p>Windows デスクトップアプリで詰まりやすい、UI スレッド、`async` / `await`、Dispatcher、タイマーの選び方をまとめたトピックです。画面フリーズや責務分割の悩みから辿れます。</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">`await` 後にどこへ戻るのかが曖昧で画面が詰まりやすい</div>
      <div class="topic-hub-point">定期処理を UI 側で回すべきかバックグラウンドへ寄せるべきか迷う</div>
      <div class="topic-hub-point">WinForms / WPF の実装を保守しやすく整理したい</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連記事</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/blog/2026/03/12/000-wpf-winforms-ui-thread-async-await-one-sheet/">WPF / WinForms の async/await と UI スレッドを一枚で整理 - await 後の戻り先、Dispatcher、ConfigureAwait、.Result / .Wait() の詰まりどころ</a>
        <a class="topic-hub-link" href="/blog/2026/03/09/001-csharp-async-await-best-practices/">C# async/await のベストプラクティス - Task.Run と ConfigureAwait の判断表</a>
        <a class="topic-hub-link" href="/blog/2026/03/12/002-periodictimer-system-threading-timer-dispatchertimer-guide/">PeriodicTimer / System.Threading.Timer / DispatcherTimer の使い分け - .NET の定期実行をまず整理</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連ページ</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/topics/ui-threading-timers/">UI スレッド / 定期処理テーマ</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/windows-app-development/">Windowsアプリ開発</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/technical-consulting/">技術相談・設計レビュー</a>
      </div>
    </div>
  </section>

  <section class="topic-hub-card" aria-labelledby="topic-native">
    <h3 id="topic-native">ネイティブ連携 / 32bit / 64bit / C++/CLI</h3>
    <p>32bit / 64bit の壁、C++/CLI ラッパー、ネイティブ DLL 連携、.NET と C/C++ の境界設計をまとめたトピックです。相互運用まわりの詰まりをまとめて辿れます。</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">32bit 資産が残っていて 64bit 化が進まない</div>
      <div class="topic-hub-point">P/Invoke と C++/CLI のどちらを選ぶべきか迷う</div>
      <div class="topic-hub-point">.NET 側とネイティブ側の境界を長期保守しやすくしたい</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連記事</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/blog/2026/03/07/000-cpp-cli-wrapper-for-native-dlls/">C# からネイティブ DLL を使うなら C++/CLI ラッパーが有力な理由 - P/Invoke と比較して整理</a>
        <a class="topic-hub-link" href="/blog/2026/03/12/003-csharp-native-aot-native-dll-from-c-cpp/">C# を Native AOT でネイティブ DLL にする方法 - UnmanagedCallersOnly で C/C++ から呼び出す</a>
        <a class="topic-hub-link" href="/blog/2026/03/12/001-activex-ocx-keep-wrap-replace-decision-table/">ActiveX / OCX を今どう扱うか - 残す・包む・置き換える判断表</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連ページ</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/topics/32bit-64bit/">32bit / 64bit テーマ</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/legacy-asset-migration/">既存資産活用・移行支援</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/technical-consulting/">技術相談・設計レビュー</a>
      </div>
    </div>
  </section>

  <section class="topic-hub-card" aria-labelledby="topic-investigation">
    <h3 id="topic-investigation">不具合調査 / 長期稼働 / 通信切り分け</h3>
    <p>再現しにくい障害、長時間運転後のクラッシュ、通信停止、異常系テスト基盤の整え方を辿るトピックです。原因調査そのものを前に進めたいときの入口になります。</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">現象は見えているが、どこを観測すべきかが定まらない</div>
      <div class="topic-hub-point">長期稼働障害やリークの調べ方を整理したい</div>
      <div class="topic-hub-point">通信停止や異常系の再現条件を切り分けたい</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連記事</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/blog/2026/03/11/001-tcp-retransmission-rfc1323-industrial-camera/">TCP 再送で産業用カメラ通信が数秒止まるとき - RFC1323 タイムスタンプと再送待ちの切り分け</a>
        <a class="topic-hub-link" href="/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/">産業用カメラ制御アプリが1か月後に突然落ちるとき（前編） - ハンドルリークの見つけ方と長期稼働向けログ設計</a>
        <a class="topic-hub-link" href="/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/">産業用カメラ制御アプリが1か月後に突然落ちるとき（後編） - Application Verifier とは何かと異常系テスト基盤の作り方</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">関連ページ</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/topics/bug-investigation-long-run/">不具合調査 / 長期稼働テーマ</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/bug-investigation/">不具合調査・原因解析</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/services/windows-app-development/">Windowsアプリ開発</a>
      </div>
    </div>
  </section>
</div>

## 迷ったときの見方

もし複数のトピックにまたがって見える場合は、いちばん「今つらい論点」に近いところから辿るのがおすすめです。  
たとえば「ActiveX を含む 32bit 資産を .NET から使いたい」なら、`COM / ActiveX / OCX` と `ネイティブ連携 / 32bit / 64bit / C++/CLI` の両方を続けて見ると、判断の輪郭がかなり揃います。
