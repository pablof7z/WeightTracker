---
type: episode-card
date: 2026-06-17
session: 18aedfc3-5869-408c-a87a-9618ad497cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/18aedfc3-5869-408c-a87a-9618ad497cfa.jsonl
salience: product
status: superseded
subjects:
  - rate-chart-rendering
  - active-cut-minichart
supersedes:
  - 2026-06-17-1-minichart-gains-swipeable-rate-of-change
related_claims: []
source_lines:
  - 346-368
captured_at: 2026-06-17T08:30:26Z
---

# Episode: Rate chart needs signed-data visual treatment, not weight-chart parity

## Prior State

User requested 'same UI (except the min/max/avg trend lines)' for the rate-of-change chart; initial implementation reused weight-chart visual grammar — gradient fill from line to plot bottom, same y-axis scaling logic, same fill-path helper.

## Trigger

Deployed to device; screenshot revealed compounding visual failures: (1) fill-to-bottom creates a giant meaningless grey area since the reference is zero not the bottom edge, (2) a one-sided-difference endpoint spike hijacks the y-domain squashing all real variation into ~15% of the chart, (3) the chart reads as positive/gaining during a cut, and (4) no zero label or scale cues exist.

## Decision

Rate-of-change chart requires a distinct visual grammar for signed data: (1) fill between the line and the zero baseline (not plot bottom) so direction is obvious, (2) clamp/winsorize derivative outliers and drop spiky one-sided endpoints so a single spike cannot hijack the y-domain, (3) make the y-domain symmetric around zero based on the clamped range so zero sits mid-chart, (4) add an explicit '0' label on the baseline.

## Consequences

- Rate chart will look fundamentally different from the weight chart despite sharing the same x-axis domain
- Central-difference smoothing strategy must guard endpoints; early-cut placeholder ('Rate appears after a few days') already exists but endpoint clamping is additional
- Fill-path helper was already refactored to be reusable; the zero-baseline fill variant is a new rendering mode
- Future signed-value charts (e.g. second derivative / acceleration) would follow the same doctrine

## Open Tail

- Landscape focus chart does not yet have the rate page — needs mirroring
- Second derivative (acceleration / plateau detection) page deferred as possible future third page

## Evidence

- transcript lines 346-368

