---
type: episode-card
date: 2026-06-13
session: 3958dfae-7703-499c-b93a-b4def20d006e
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/3958dfae-7703-499c-b93a-b4def20d006e.jsonl
salience: root-cause
status: superseded
subjects:
  - weight-chart-rendering
  - active-cut-minichart
  - landscape-focus-chart
supersedes: []
related_claims: []
source_lines:
  - 1-338
captured_at: 2026-06-13T21:54:50Z
---

# Episode: Weight chart line switched from raw readings to EWMA smooth line

## Prior State

Weight chart lines were drawn directly from raw `inCutReadings` data using `.monotone` interpolation. When consecutive days had the same whole-pound value, monotone interpolation produced literal flat segments, creating a blocky staircase appearance.

## Trigger

User reported chart looked blocky. Initial fix (smoothing the fill path with Catmull-Rom curves) had no visible effect, forcing a revised root-cause analysis: the line itself—not the fill—was stepping because repeated identical weight values caused monotone interpolation to draw flat segments.

## Decision

Replaced the raw-reading LineMark with an EWMA (exponentially weighted moving average) smoothed trend line, while retaining individual PointMarks for raw readings. Applied to both `ActiveCutMinichart` and `LandscapeFocusChart`, including their `areaFillPath` functions which now draw gradient fills from the smoothed line rather than raw data.

## Consequences

- Chart displays a smooth trend curve instead of a staircase when weight plateaus for multiple days
- Raw daily readings remain visible as individual dots
- EWMA smoothing introduces a slight lag/averaging in the visual trend line
- Pattern now mirrors the existing WeightChart moving-average approach

## Open Tail

*(none)*

## Evidence

- transcript lines 1-338

