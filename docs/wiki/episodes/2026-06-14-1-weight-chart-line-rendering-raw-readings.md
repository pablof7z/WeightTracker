---
type: episode-card
date: 2026-06-14
session: 3958dfae-7703-499c-b93a-b4def20d006e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/3958dfae-7703-499c-b93a-b4def20d006e.jsonl
salience: product
status: active
subjects:
  - weight-chart-smoothing
  - active-cut-minichart
  - landscape-focus-chart
supersedes:
  - 2026-06-14-1-weight-chart-line-smoothing-from-staircase
related_claims: []
source_lines:
  - 1-429
captured_at: 2026-06-14T07:08:56Z
---

# Episode: Weight chart line rendering: raw readings → centered 5-day moving average

## Prior State

Weight chart plotted raw daily readings with `.monotone` interpolation on LineMark and straight `addLine` segments for the area fill path. When consecutive days shared the same weight value, monotone interpolation produced literal flat segments, creating a blocky/staircase appearance.

## Trigger

User reported chart looked blocky. Initial diagnosis (jagged fill path) was wrong — visual test confirmed no change. Second attempt (EWMA α=0.25) introduced visible lag on declining trends, causing line to not follow actual points. Third attempt (centered 5-day MA) still showed dots offset from the smooth line since dots used raw data while line used averaged data.

## Decision

Both the line and the dots in the actual-data series now use a centered 5-day moving average (each point = mean of itself ± 2 surrounding days). The area fill path also draws from the same smoothed series. This replaces raw-readings-with-monotone-interpolation as the chart's data source for the actual weight trace.

## Consequences

- Staircase flat-segment artifact eliminated; chart shows gradual slopes between weight changes
- Dots sit exactly on the smooth line since both derive from the same averaged data
- Centered window avoids the lag that EWMA introduced on declining trends
- Raw daily readings are no longer directly visible as individual points on the line — users see averaged values
- Catmull-Rom fill path change from first (incorrect) fix remains in place as well

## Open Tail

- Whether users need or expect to see the exact raw reading values alongside the smoothed line
- Whether the centered 5-day window behaves acceptably at the chart edges (fewer than 5 days available)

## Evidence

- transcript lines 1-429

