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
  - weight-derivative-computation
supersedes:
  - 2026-06-17-1-rate-of-change-chart-as-swipeable
related_claims: []
source_lines:
  - 1-13
  - 346-368
  - 470-474
  - 517-531
  - 648-657
captured_at: 2026-06-17T08:51:31Z
---

# Episode: Rate-of-change chart: first-derivative page with robust regression

## Prior State

The Today screen showed only absolute weight (smoothed line + projections). No rate-of-change visualization existed. A naive point-difference derivative would be the obvious first approach but is unusable for daily weigh-in data.

## Trigger

User requested seeing 'the rate of speed at which my weight is changing during the cut.' Initial implementation using short-window central differences produced a positive rate (+1.9 lb/wk) during an active cut — revealing that daily water-weight noise (±1–2 lb/day → ±7–14 lb/wk apparent rate) completely dominates and can flip the sign of the true trend (~0.1 lb/day). Subsequent visual iterations exposed fill-direction, y-domain, smoothing, and x-domain problems.

## Decision

Added a swipeable second page to ActiveCutMinichart (paged TabView with dots) showing the first derivative. Rate is computed via ~2-week least-squares regression over the already-smoothed weight line (not raw readings), then lightly re-smoothed with a ±2 moving average, rendered with monotone interpolation and no per-point dots. Fill renders as area under the curve (not band-to-zero, not fill-to-bottom). Y-domain fits actual data range with zero included (not forced symmetric). X-domain scoped to the rate data's own range (not the weight page's projection-extended domain). Current rate displayed in both lb/wk and lb/day on one page.

## Consequences

- Short-window or point-difference derivative approaches are permanently unsuitable for daily weigh-in data — the noise floor exceeds the signal by ~100×
- Rate and weight pages now have different x-domains (rate ends at today, weight extends to projection date), so 'today' marker does not align across pages
- LandscapeFocusChart still only shows weight — rate page is portrait-minichart-only for now
- Second derivative (acceleration/plateau detection) remains unimplemented but was identified as a potential third page

## Open Tail

- Mirror the rate page onto LandscapeFocusChart
- Potential third page for second derivative (acceleration/stall detection)
- Consider whether aligning 'today' across pages matters more than edge-to-edge data coverage

## Evidence

- transcript lines 1-13
- transcript lines 346-368
- transcript lines 470-474
- transcript lines 517-531
- transcript lines 648-657

