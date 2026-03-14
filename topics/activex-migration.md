---
layout: detail-page
lang: ja
translation_key: topic-activex-migration
permalink: /topics/activex-migration/
title: "ActiveX / 移行テーマ | KomuraSoft"
page_name: "ActiveX / 移行テーマ"
page_eyebrow: "Topic"
schema_type: "CollectionPage"
breadcrumb_parent_label: "技術トピック"
breadcrumb_parent_url: "/topics/"
description: "COM / ActiveX / OCX を残すか、ラップするか、置き換えるかを検討するための技術テーマページです。保守・移行の考え方と関連ページを整理しています。"
page_keywords:
  - ActiveX
  - COM
  - OCX
  - 移行
related_pages:
  - title: "技術トピック"
    url: "/topics/"
  - title: "技術相談・設計レビュー"
    url: "/services/technical-consulting/"
  - title: "既存資産活用・移行支援"
    url: "/services/legacy-asset-migration/"
related_articles:
  - title: "COM / ActiveX 保守・移行の判断表"
    url: "/blog/2026/03/12/001-activex-ocx-keep-wrap-replace-decision-table/"
  - title: "COM STA / MTA の基本"
    url: "/blog/2026/01/31/000-sta-mta-com-relationship/"
  - title: "C++/CLI ラッパーを使う判断"
    url: "/blog/2026/03/07/000-cpp-cli-wrapper-for-native-dlls/"
---

## このテーマで整理したいこと

ActiveX / OCX を含む既存資産では、「全部作り直す」か「何も触らない」かの二択に見えがちです。
実際には、その間に多くの選択肢があります。

- まずは現状維持で保守する
- 外側だけラップして新しいコードから扱いやすくする
- 周辺機能から段階的に置き換える
- ネイティブ境界だけ別案で整理する

## 相談でよく出る論点

- 既存 ActiveX / OCX をどこまで延命するべきか
- 新しい .NET 側からどう安全に呼び出すか
- 置き換え対象と、当面残す対象をどう切り分けるか
- COM まわりのスレッド境界や責務をどう整理するか

## 向いている進め方

いきなり全面リプレースを決めるより、現状の境界を整理して、保守・ラップ・置換のどれが妥当かを見極める方が進めやすいことが多いです。
技術相談ページと移行支援ページ、関連する記事を合わせて見ると、方針の比較がしやすくなります。
