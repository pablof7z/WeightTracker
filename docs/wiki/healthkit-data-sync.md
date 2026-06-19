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
updated: 2026-06-17
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:40f50066fa357afb7e9e270beda982042834ee1c693a6b4dc3282abc07aeb628
  - session:a37353e546d60ed540b9a3be5c3e6940a6eb6ba5d3e7fd2facd082840cd044d9
  - session:18aedfc3-5869-408c-a87a-9618ad497cfa
  - session:00f6109b-0c81-40e9-a6c3-1c98c927c324
---

# HealthKit Data Sync

## HealthKit Data Sync

Re-importing activity data from Apple Health overwrites existing data for those days before inserting fresh records, except that manually-entered readings (sourced as 'manual', 'watch', or 'importCSV') are never overwritten by a HealthKit sample. Days with an externally-sourced HealthKit reading (e.g., from a scale) still update when HealthKit reports a meaningfully different value exceeding a 1g / 0.001 kg threshold. HealthKit samples are sorted most-recent-first before processing so that when multiple HK sources exist for the same day, the latest timestamp consistently wins. The HealthKit ingest observer skips re-importing samples authored by the app itself when a reading for that day already exists locally, to prevent round-trip duplicates. The `reading(on:)` repository method matches dates within a ±12-hour window instead of requiring an exact timestamp equality, making it robust against DST shifts. Deleting or editing a reading in-app also deletes the corresponding sample from Apple Health to prevent orphaned ghost entries. A one-time migration on app launch cleaned up existing duplicate readings, reducing the total from 530 to 490 and in-cut readings from 90 to 50, keeping manual entries over healthKit ones where duplicates existed.

The faint dashed weight overlay line on the rate page visualises trend data. The 'in-cut' metric in weight tracking identifies readings that fall within a deficit band. Reading.date is forced to dayStart via Calendar.current, which is a timezone-sensitive duplicate trap when the same UTC moment maps to different local days. The rate page performs per-day deduplication before differentiating to ensure one reading per day is used in the rate calculation. <!-- [^00f61-2] -->

<!-- citations: [^40f50-1] [^40f50-2] [^40f50-3] [^a3735-1] [^18aed-24] [^00f61-1] -->
