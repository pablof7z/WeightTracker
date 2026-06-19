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
updated: 2026-06-17
verified: 2026-06-13
compiled-from: conversation
sources:
  - session:e2ed7c73-91d8-4046-991f-26b0a47689e6
  - session:3059739a53f0b6574db54c73cc9b1ffca838e9ed56cf54ad9be63d9dc3624f35
  - session:1c6f27ba16d4c91d8a3f569bd1e199790868b60e22d2cad4a2e386c4d67b14cb
  - session:18aedfc3-5869-408c-a87a-9618ad497cfa
  - session:1a7ed5a0-cb16-4a32-8576-3fbf4e24310f
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

The page-swipe gesture is contained inside the chart's TabView so that swiping on the chart flips pages while the rest of the Today screen retains its day-to-day date swipe. <!-- [^18aed-4] -->

## Rate-of-Change Feature Scope

The rate-of-change feature is scoped to the portrait minichart on the main Today screen; the landscape focus chart still only shows weight. <!-- [^18aed-5] -->

## Chart Pan & Pinch Gestures

Dragging left or right anywhere on the chart pans the time window through time, with a 20pt minimum distance to prevent conflicts with tap-to-inspect.

Pinching resizes the duration span between 3 and 180 days, matching map gesture direction where pinch-in equals a shorter span.

If a pinch resizes the span to within 10% of a preset (7d / 14d / 30d), the span snaps to that preset with a spring animation.

The preset picker dims to 45% opacity when the user is in custom pan/span mode as a signal that they have departed from a preset.

Tapping any preset pill resets pan offset and custom span back to zero.

Double-tapping the chart resets everything: window, pan, span, and any tap selection. <!-- [^1a7ed-1] -->
