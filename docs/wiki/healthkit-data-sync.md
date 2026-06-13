---
title: HealthKit Data Sync
slug: healthkit-data-sync
topic: healthkit-data-sync
summary: Re-importing activity data from Apple Health overwrites existing data for those days before inserting fresh records, except that manually-entered readings (sour
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-05-15
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:40f50066fa357afb7e9e270beda982042834ee1c693a6b4dc3282abc07aeb628
  - session:a37353e546d60ed540b9a3be5c3e6940a6eb6ba5d3e7fd2facd082840cd044d9
---

# HealthKit Data Sync

## HealthKit Data Sync

Re-importing activity data from Apple Health overwrites existing data for those days before inserting fresh records, except that manually-entered readings (sourced as 'manual', 'watch', or 'importCSV') are never overwritten by a HealthKit sample. Days with an externally-sourced HealthKit reading (e.g., from a scale) still update when HealthKit reports a meaningfully different value exceeding a 1g / 0.001 kg threshold. HealthKit samples are sorted most-recent-first before processing so that when multiple HK sources exist for the same day, the latest timestamp consistently wins.

The app's HealthKit step count query sums data from all sources (iPhone, Apple Watch, third-party apps), which can result in higher numbers than the Apple Health Steps view that uses a preferred source priority to avoid double-counting.

The HKStatisticsCollectionQuery in ActivityHealthKit.swift should add source filtering to only include the preferred/primary source, matching how the Apple Health app displays steps.

<!-- citations: [^40f50-1] [^40f50-2] [^40f50-3] [^a3735-1] -->
