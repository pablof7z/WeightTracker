---
type: episode-card
date: 2026-06-14
session: 3958dfae-7703-499c-b93a-b4def20d006e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/3958dfae-7703-499c-b93a-b4def20d006e.jsonl
salience: product
status: superseded
subjects:
  - weight-chart-line-rendering
  - active-cut-minichart
  - landscape-focus-chart
supersedes:
  - 2026-06-13-1-weight-chart-line-switched-from-raw
related_claims: []
source_lines:
  - 1-2
  - 111-121
  - 257-261
  - 357-369
captured_at: 2026-06-14T06:40:32Z
---

# Episode: Weight chart line smoothing: from staircase monotone to centered moving average

## Prior State

The weight chart used SwiftUI LineMark with .monotone interpolation on raw daily readings, and the gradient fill area underneath used straight addLine calls between points. When consecutive days had the same weight value (whole-pound readings), monotone interpolation drew literal flat segments, producing a staircase/blocky appearance.

## Trigger

User reported the chart looked 'blocky' instead of smooth. Two successive misdiagnoses followed: first that the fill path's straight-line segments caused the blockiness (fixing it changed nothing), then that an EWMA (α=0.25) trend line would solve it (it lagged behind actual points on declining trends, causing visible detachment from the data dots).

## Decision

Adopted a centered 5-day moving average (mean of each point ± 2 days) for the line rendering, while keeping individual raw weight points as visible dots. The fill path was also converted to Catmull-Rom curves to match. Applied to both ActiveCutMinichart and LandscapeFocusChart.

## Consequences

- Flat staircase segments from repeated weight values now render as gradual slopes
- Line stays within ~0.3 lb of each actual reading — no perceivable lag since the average is centered, not trailing
- Individual raw readings remain visible as dots, preserving data fidelity
- Durable root-cause finding: monotone interpolation on data with many repeated values produces visual staircases; a centered window average is the correct smoothing strategy for this data shape

## Open Tail

- User has not yet confirmed the centered-5-day version looks acceptable

## Evidence

- transcript lines 1-2
- transcript lines 111-121
- transcript lines 257-261
- transcript lines 357-369

