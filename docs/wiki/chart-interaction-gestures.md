---
title: Chart Interaction Gestures
slug: chart-interaction-gestures
topic: ui-components
summary: FullscreenChart.swift and all tap-to-fullscreen gestures across 5 views have been removed, replaced with a landscape rotation hint.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-13
updated: 2026-06-13
verified: 2026-06-13
compiled-from: conversation
sources:
  - session:e2ed7c73-91d8-4046-991f-26b0a47689e6
  - session:3059739a53f0b6574db54c73cc9b1ffca838e9ed56cf54ad9be63d9dc3624f35
  - session:1c6f27ba16d4c91d8a3f569bd1e199790868b60e22d2cad4a2e386c4d67b14cb
---

# Chart Interaction Gestures

## Fullscreen Interaction

FullscreenChart.swift and all tap-to-fullscreen gestures across 5 views have been removed, replaced with a landscape rotation hint. <!-- [^e2ed7-1] -->

## Bar Tap Detail Sheet (Cuts > Activity)

Tapping one of the 7-day bars on the Cuts > Activity screen opens a sheet displaying that day's date, steps count, target, goal-met status with a colored icon, active energy in kcal, and exercise minutes. A 'No step data for this day' fallback message is shown for empty days. <!-- [^30597-1] -->

## Bar Tap Hint

A subtle 'Tap a bar for details' hint appears below the 7-day average on the activity screen. <!-- [^30597-2] -->

## Implementation Note

The DayActivitySheet and .onTapGesture edits referenced in recent conversation history do not exist in the current ActivityCard.swift on master. <!-- [^30597-3] -->

## Today Screen Day Navigation

The Today screen has no left/right buttons for navigating between previous and next days; swipe gestures are used instead. <!-- [^1c6f2-1] -->
