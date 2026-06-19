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
  - 2026-06-17-1-rate-chart-needs-signed-data-visual
related_claims: []
source_lines:
  - 1-13
  - 346-368
  - 396-514
captured_at: 2026-06-17T08:39:18Z
---

# Episode: Rate-of-change chart page on Today minichart

## Prior State

The Today screen minichart showed only weight (smoothed line + projection trend lines + gradient fill to plot bottom). No rate-of-change visualization existed anywhere in the app.

## Trigger

User requested: 'I want to be able to slide on the daily chart in the main screen and see the rate of speed at which my weight is changing during the cut.' Initial deployment revealed the chart read as gaining (+1.9 lb/wk) during a cut, the fill was a meaningless flood from line to bottom, and an outlier spike squashed the scale flat.

## Decision

Added a two-page swipeable TabView (Weight ↔ Rate) with page dots to ActiveCutMinichart. The Rate page shows the first derivative of weight using a ~2-week least-squares regression (replacing the initial short-window central difference). Visual: fill rendered between the line and a zero baseline (not plot bottom), y-domain symmetric around zero scaled by 90th-percentile magnitude (not max), dashed zero rule with '0' label, corner readout showing both lb/wk and lb/day. Min/max/avg trend lines and target rule excluded per user request.

## Consequences

- Short-window (±1 day) derivative is unreliable for weight data — daily water noise (±1–2 lb) swamps the ~0.1 lb/day real trend and can flip the sign at random; multi-week regression is required.
- Fill-to-bottom is meaningless for signed rate data; fill-to-zero-baseline is now the pattern for this chart type.
- Only the portrait minichart has the rate page; the landscape focus chart still shows weight only.
- User clarified they wanted the first derivative (velocity: lb/wk), not the second derivative (acceleration); a potential third page for acceleration was flagged but not built.

## Open Tail

- Mirror the rate page onto LandscapeFocusChart
- Potential third page for second derivative (acceleration/plateau detection)
- Visual tuning of readout placement and fill aesthetics for the signed-value chart

## Evidence

- transcript lines 1-13
- transcript lines 346-368
- transcript lines 396-514

