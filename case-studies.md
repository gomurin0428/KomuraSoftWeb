---
layout: detail-page
lang: ja
translation_key: case-studies-hub
permalink: /case-studies/
title: "技術事例 | KomuraSoft"
page_name: "技術事例"
page_eyebrow: "Case Studies"
schema_type: "CollectionPage"
description: "KomuraSoft が対応してきた不具合調査、通信異常の切り分け、長期稼働障害の解析、異常系テスト基盤整備の技術事例をまとめたページです。"
page_keywords:
  - 技術事例
  - 不具合調査
  - 長期稼働障害
  - 通信異常
related_pages:
  - title: "不具合調査・原因解析"
    url: "/services/bug-investigation/"
  - title: "Windowsアプリ開発"
    url: "/services/windows-app-development/"
  - title: "技術トピック"
    url: "/topics/"
related_articles:
  - title: "産業用カメラ通信の数秒停止を切り分けた事例"
    url: "/blog/2026/03/11/001-tcp-retransmission-rfc1323-industrial-camera/"
  - title: "長期稼働後クラッシュをハンドルリークまで追った事例"
    url: "/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/"
  - title: "Application Verifier を使った異常系テスト基盤の事例"
    url: "/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/"
---

## 扱っている事例の傾向

KomuraSoft の技術事例は、単純なバグ修正よりも、現場で見えにくい障害の切り分けや、再発防止のための基盤整備に寄っています。

<div class="case-studies-card">
  <p class="case-studies-note">各事例は、症状、制約、観測、切り分け、改善までを 1 ページで追えるように整理しています。詳しい技術背景は元記事へ戻れます。</p>
  <div class="case-study-list">
    <article class="case-study-item">
      <h2 class="case-study-title"><a href="/case-studies/industrial-camera-tcp-stall/">事例 1: 産業用カメラ通信の数秒停止を切り分けた事例</a></h2>
      <p class="case-study-body">数秒だけ止まる通信異常について、再送待ち時間と OS 側の通信条件を切り分け、どこに手を入れると改善に効くかを整理したケースです。</p>
      <p class="case-study-body">詳しい技術背景: <a href="/blog/2026/03/11/001-tcp-retransmission-rfc1323-industrial-camera/">TCP 再送で産業用カメラ通信が数秒止まるとき</a></p>
      <div class="section-related-links-list">
        <a class="section-related-link" href="/services/bug-investigation/">不具合調査・原因解析</a>
        <a class="section-related-link" href="/services/windows-app-development/">Windowsアプリ開発</a>
      </div>
    </article>
    <article class="case-study-item">
      <h2 class="case-study-title"><a href="/case-studies/long-run-crash-handle-leak/">事例 2: 長期稼働後クラッシュをハンドルリークまで追った事例</a></h2>
      <p class="case-study-body">一か月単位の連続運転後にだけ落ちる障害を、観測ログの増強と再現圧縮でハンドルリーク調査へ絞り込んだケースです。</p>
      <p class="case-study-body">詳しい技術背景: <a href="/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/">産業用カメラ制御アプリが1か月後に突然落ちるとき（前編）</a></p>
      <div class="section-related-links-list">
        <a class="section-related-link" href="/services/bug-investigation/">不具合調査・原因解析</a>
        <a class="section-related-link" href="/services/windows-app-development/">Windowsアプリ開発</a>
      </div>
    </article>
    <article class="case-study-item">
      <h2 class="case-study-title"><a href="/case-studies/application-verifier-failure-path-testing/">事例 3: Application Verifier を使った異常系テスト基盤の事例</a></h2>
      <p class="case-study-body">単発の修正だけで終わらせず、異常系テスト基盤を先に整えて次回以降も追いやすくしたケースです。</p>
      <p class="case-study-body">詳しい技術背景: <a href="/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/">Application Verifier を使った異常系テスト基盤の作り方</a></p>
      <div class="section-related-links-list">
        <a class="section-related-link" href="/services/bug-investigation/">不具合調査・原因解析</a>
        <a class="section-related-link" href="/services/technical-consulting/">技術相談・設計レビュー</a>
      </div>
    </article>
  </div>
</div>
