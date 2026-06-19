---
type: episode-card
date: 2026-06-17
session: 1a7ed5a0-cb16-4a32-8576-3fbf4e24310f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/1a7ed5a0-cb16-4a32-8576-3fbf4e24310f.jsonl
salience: root-cause
status: active
subjects:
  - chart-area-fill
  - safe-area-rendering
supersedes: []
related_claims: []
source_lines:
  - 153-182
captured_at: 2026-06-17T08:55:50Z
---

# Episode: Chart Area Fill Must Cover Full View Including Safe Area

## Prior State

areaFillPath used pts[0].x (the first data point's x-coordinate) as the left fill boundary, which left an unfilled gap in the safe-area strip left of the y-axis.

## Trigger

Visual bug — grayed gradient area did not cover the left part of the chart (safe-area region).

## Decision

Fill boundary changed from pts[0].x to 0 (the chart view's screen-left edge under .ignoresSafeArea()), so the gradient extends fully behind the y-axis and safe area while data-point positions remain anchored to plotFrame.minX.

## Consequences

- Gradient fill now seamlessly covers the full chart view including safe-area margins
- Pattern applies to future chart backgrounds: fill boundaries should use view edges, not data-point positions

## Open Tail

*(none)*

## Evidence

- transcript lines 153-182

