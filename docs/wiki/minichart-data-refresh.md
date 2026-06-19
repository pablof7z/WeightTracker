---
title: Minichart Data Refresh
slug: minichart-data-refresh
topic: ui-components
summary: Minichart data refreshes after weigh-in without requiring a restart, including animation
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-13
updated: 2026-06-17
verified: 2026-06-13
compiled-from: conversation
sources:
  - session:e2ed7c73-91d8-4046-991f-26b0a47689e6
  - session:1c6f27ba16d4c91d8a3f569bd1e199790868b60e22d2cad4a2e386c4d67b14cb
  - session:cab583fb4c8c03ad2012aa908913c6eb6ff4deeb13a6da30570b8291a4319bfa
  - session:3958dfae-7703-499c-b93a-b4def20d006e
  - session:18aedfc3-5869-408c-a87a-9618ad497cfa
---

# Minichart Data Refresh

## Data Refresh

Minichart data refreshes after weigh-in without requiring a restart, including animation. The chart updates immediately to reflect a newly entered weight without requiring an app restart. When a new weight reading is saved, inCutReadings and projection are recomputed so that the chart renders the new data immediately. The chart line animates smoothly (ease-in-out over 0.4 seconds) when a new reading is added, rather than updating instantly or with complex animation. Weight chart lines use a smoothed (EWMA) trend line for the path and fill area, while keeping individual raw weight dots visible. The weight log data view is located on the Progress screen (not the Today screen). The Today-screen minichart is a swipeable two-page view with page dots in the top gutter: page 1 shows weight, and page 2 shows the first derivative (rate of change) of weight. The page-swipe gesture for flipping between weight and rate charts is contained within the chart TabView, keeping it independent from the Today screen's day-to-day date swipe.

<!-- citations: [^e2ed7-3] [^1c6f2-2] [^cab58-1] [^3958d-1] [^18aed-12] [^18aed-21] -->
