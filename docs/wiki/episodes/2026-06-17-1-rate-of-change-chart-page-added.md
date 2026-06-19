---
type: episode-card
date: 2026-06-17
session: 18aedfc3-5869-408c-a87a-9618ad497cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/18aedfc3-5869-408c-a87a-9618ad497cfa.jsonl
salience: product
status: active
subjects:
  - active-cut-minichart
  - rate-of-change-chart
  - daily-chart-interaction
supersedes:
  - 2026-06-17-1-rate-of-change-chart-first-derivative
related_claims: []
source_lines:
  - 1-700
captured_at: 2026-06-17T09:30:41Z
---

# Episode: Rate-of-change chart page added to minichart

## Prior State

Only weight visualization existed on the minichart; no way to see rate of weight change during a cut.

## Trigger

User requested ability to slide on the daily chart and see the rate at which weight is changing during a cut (initially described as second derivative, clarified as first derivative — rate of change).

## Decision

Added a swipeable 2-page minichart: page 1 = weight chart (unchanged), page 2 = rate-of-change chart showing both lb/wk and lb/day. Rate computed from the smoothed weight line, day-deduplicated before differentiation, rendered with Catmull-Rom interpolation. Each page has its own x-domain (weight includes projection window, rate ends at today). A faint dashed weight-overlay line appears on the rate page with a legend.

## Consequences

- Fill direction had to be inverted for the rate chart: signed quantity fills from curve to zero baseline (not top), since data is always-negative during a cut.
- Rate page uses its own x-domain (data span only) so the curve fills edge-to-edge, trading off day-alignment with the weight page.
- Smoothing the rate required deduplicating readings per calendar day first, otherwise the ~2 readings/day made the moving average span only ~2.5 real days instead of the intended window.
- Page dots and accessibility label ('Swipe left for rate of change') added for discoverability.

## Open Tail

- Forecast widget shows −0.34 lb/day while rate page shows −0.27 — two different rate calculations that could be unified.

## Evidence

- transcript lines 1-700

