<div class="topic-hub-grid">
  <section class="topic-hub-card" aria-labelledby="topic-com">
    <h3 id="topic-com">COM / ActiveX / OCX and staged legacy migration</h3>
    <p>This topic groups the practical questions around existing Windows assets: what to keep, what to wrap, and what to replace first. It connects terminology, migration decisions, and thread-boundary issues in one path.</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">you are unsure how to handle an existing ActiveX / OCX asset going forward</div>
      <div class="topic-hub-point">COM terminology and STA / MTA concerns are getting mixed together</div>
      <div class="topic-hub-point">you want a staged migration path instead of an all-or-nothing rewrite</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related articles</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/en/blog/2026/03/13/000-what-is-com-activex-ocx/">What COM / ActiveX / OCX Are - A Practical Guide to the Differences and Relationships</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/12/001-activex-ocx-keep-wrap-replace-decision-table/">How to Handle ActiveX / OCX Today - A Decision Table for Keep / Wrap / Replace</a>
        <a class="topic-hub-link" href="/en/blog/2026/01/31/000-sta-mta-com-relationship/">COM STA/MTA Basics - Threading Models and How to Avoid Hangs</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related pages</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/topics/activex-migration/">ActiveX Migration</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/legacy-asset-migration/">Legacy Asset Reuse & Migration Support</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/technical-consulting/">Technical Consulting & Design Review</a>
      </div>
    </div>
  </section>

  <section class="topic-hub-card" aria-labelledby="topic-dotnet">
    <h3 id="topic-dotnet">.NET / Generic Host / application structure</h3>
    <p>This topic groups the design questions that appear once a .NET application grows a little: DI, configuration, logging, startup structure, and background work. It is a good path when the real issue is how the application should be assembled as a whole.</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">too much logic is accumulating in `Main` or `Program.cs`</div>
      <div class="topic-hub-point">you are unsure where resident work or `BackgroundService` should live</div>
      <div class="topic-hub-point">you want DI, configuration, and logging to connect cleanly</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related articles</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/en/blog/2026/03/14/000-dotnet-generic-host-what-is/">What the .NET Generic Host Is - DI, Configuration, Logging, and BackgroundService Explained</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/12/002-generic-host-backgroundservice-desktop-app/">Why It Is Worth Bringing Generic Host / BackgroundService into a Desktop App - Startup, Lifetime, and Graceful Shutdown Become Much Easier to Organize</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/09/001-csharp-async-await-best-practices/">C# async/await Best Practices - A Decision Table for Task.Run and ConfigureAwait</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related pages</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/topics/generic-host-app-architecture/">Generic Host & App Architecture</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/windows-app-development/">Windows App Development</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/technical-consulting/">Technical Consulting & Design Review</a>
      </div>
    </div>
  </section>

  <section class="topic-hub-card" aria-labelledby="topic-ui">
    <h3 id="topic-ui">WPF / WinForms / UI thread and periodic work</h3>
    <p>This topic groups the places where Windows desktop apps tend to get sticky: the UI thread, `async` / `await`, Dispatcher usage, and timer choices. It is a practical path when freezes or responsibility boundaries are the real pain point.</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">it is unclear where execution returns after `await`, and the UI keeps getting blocked</div>
      <div class="topic-hub-point">you are unsure whether periodic work belongs in the UI layer or in the background</div>
      <div class="topic-hub-point">you want a more maintainable shape for WinForms or WPF code</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related articles</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/en/blog/2026/03/12/000-wpf-winforms-ui-thread-async-await-one-sheet/">WPF / WinForms async/await and the UI Thread in One Sheet - Where Continuations Return, Dispatcher, ConfigureAwait, and Why .Result / .Wait() Get Stuck</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/09/001-csharp-async-await-best-practices/">C# async/await Best Practices - A Decision Table for Task.Run and ConfigureAwait</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/12/002-periodictimer-system-threading-timer-dispatchertimer-guide/">How to Choose Between PeriodicTimer, System.Threading.Timer, and DispatcherTimer - First Organize Periodic Work in .NET</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related pages</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/topics/ui-threading-timers/">UI Threading & Timers</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/windows-app-development/">Windows App Development</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/technical-consulting/">Technical Consulting & Design Review</a>
      </div>
    </div>
  </section>

  <section class="topic-hub-card" aria-labelledby="topic-native">
    <h3 id="topic-native">Native integration / 32-bit / 64-bit / C++/CLI</h3>
    <p>This topic covers the boundary decisions around 32-bit / 64-bit constraints, C++/CLI wrappers, native DLL integration, and .NET to C/C++ interop. It is useful when the real blocker is the edge between systems rather than the feature itself.</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">a 32-bit dependency is blocking 64-bit progress</div>
      <div class="topic-hub-point">you are deciding between P/Invoke and C++/CLI</div>
      <div class="topic-hub-point">you want a boundary that remains maintainable over time</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related articles</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/en/blog/2026/03/07/000-cpp-cli-wrapper-for-native-dlls/">Why a C++/CLI Wrapper Is Often the Best Way to Use a Native DLL from C# - A Practical Comparison with P/Invoke</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/12/003-csharp-native-aot-native-dll-from-c-cpp/">How to Turn C# into a Native DLL with Native AOT - Calling UnmanagedCallersOnly Exports from C/C++</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/12/001-activex-ocx-keep-wrap-replace-decision-table/">How to Handle ActiveX / OCX Today - A Decision Table for Keep / Wrap / Replace</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related pages</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/topics/32bit-64bit/">32-bit / 64-bit Interoperability</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/legacy-asset-migration/">Legacy Asset Reuse & Migration Support</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/technical-consulting/">Technical Consulting & Design Review</a>
      </div>
    </div>
  </section>

  <section class="topic-hub-card" aria-labelledby="topic-investigation">
    <h3 id="topic-investigation">Bug investigation / long-running failures / communication diagnosis</h3>
    <p>This topic follows the work of narrowing down hard production problems: intermittent failures, long-run crashes, communication stalls, and failure-path test foundations. It is a good starting point when the real need is investigation, not just implementation.</p>
    <div class="topic-hub-points">
      <div class="topic-hub-point">you can see the symptom, but not yet where to observe it properly</div>
      <div class="topic-hub-point">you need a practical way to investigate leaks or long-run failures</div>
      <div class="topic-hub-point">you are trying to narrow down communication stoppages or rare abnormal cases</div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related articles</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link" href="/en/blog/2026/03/11/001-tcp-retransmission-rfc1323-industrial-camera/">When Industrial Camera TCP Traffic Stops for Several Seconds - How to Narrow Down Retransmission Waits with RFC1323 Timestamps</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/">When an Industrial Camera Control App Suddenly Crashes After a Month (Part 1) - How to Find a Handle Leak and Design Logging for Long-Running Operation</a>
        <a class="topic-hub-link" href="/en/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/">When an Industrial Camera Control App Suddenly Crashes After a Month (Part 2) - What Application Verifier Is and How to Build Failure-Path Test Infrastructure</a>
      </div>
    </div>
    <div class="topic-hub-link-group">
      <p class="topic-hub-link-group-title">Related pages</p>
      <div class="topic-hub-links">
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/topics/bug-investigation-long-run/">Bug Investigation & Long-Run Failures</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/bug-investigation/">Bug Investigation & Root Cause Analysis</a>
        <a class="topic-hub-link topic-hub-link-secondary" href="/en/services/windows-app-development/">Windows App Development</a>
      </div>
    </div>
  </section>
</div>

## How to use this hub when several themes overlap

If your situation spans multiple areas, start from the topic closest to the current bottleneck.  
For example, if you need to use a 32-bit ActiveX asset from newer .NET code, it usually makes sense to read both `COM / ActiveX / OCX and staged legacy migration` and `Native integration / 32-bit / 64-bit / C++/CLI` in sequence.
