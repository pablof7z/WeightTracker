---
type: episode-card
date: 2026-06-17
session: 18aedfc3-5869-408c-a87a-9618ad497cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/18aedfc3-5869-408c-a87a-9618ad497cfa.jsonl
salience: product
status: superseded
subjects:
  - active-cut-minichart
  - rate-of-change-chart
  - weight-derivative-display
supersedes:
  - 2026-06-17-1-rate-of-change-chart-page-on
related_claims: []
source_lines:
  - 1-651
captured_at: 2026-06-17T08:47:26Z
---

# Episode: Rate-of-change chart as swipeable second page on Today minichart

## Prior State

The Today screen's ActiveCutMinichart showed only weight — no way to visualize how fast weight was changing during a cut.

## Trigger

User requested seeing the rate of speed at which weight is changing during a cut (initially described as 'second derivative' but clarified in words as first derivative — velocity, not acceleration).

## Decision

Add a first-derivative (rate-of-change) chart as a swipeable second page inside the minichart (paged TabView with page dots). The rate page shows both lb/wk and lb/day in a single readout, excludes the weight chart's trend lines and target rule, and adds a dashed zero baseline. Computed as a ~2-week least-squares regression on the already-smoothed weight line with an additional ±2 moving-average smoothing pass, rendered with Catmull-Rom interpolation (no per-point dots).

## Consequences

- Short-window derivatives (±1 day) on raw weight data produce sign-flipped and meaningless results because daily water-weight noise (±1–2 lb) swamps the ~0.1 lb/day signal — any future rate-of-change computation must use multi-week regression on smoothed data, not point differences.
- Y-domain for a signed rate chart must fit the actual data range and include zero, not force symmetry around zero (during a cut the 'gaining' half is empty whitespace).
- Fill gradient for a signed rate must go to the zero baseline, not the plot bottom (fill-to-bottom is meaningless area for a derivative).
- LandscapeFocusChart still only shows weight — no rate page mirrored yet.

## Open Tail

- Gradient still rendering on the wrong side (top of chart instead of between line and zero) — needs fill-path baseline fix
- Chart doesn't go edge-to-edge — white gap on the right edge
- LandscapeFocusChart rate-page mirroring not yet implemented
- Possible third page for second derivative (acceleration/stall detection) mentioned but deferred

## Evidence

- transcript lines 1-651

