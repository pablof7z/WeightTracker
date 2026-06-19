---
type: episode-card
date: 2026-06-17
session: 18aedfc3-5869-408c-a87a-9618ad497cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/18aedfc3-5869-408c-a87a-9618ad497cfa.jsonl
salience: product
status: superseded
subjects:
  - rate-of-change-chart
  - active-cut-minichart
supersedes: []
related_claims: []
source_lines:
  - 1-13
  - 160-164
  - 269-295
captured_at: 2026-06-17T08:23:16Z
---

# Episode: Rate-of-change chart added as swipeable second page to minichart

## Prior State

The ActiveCutMinichart on the Today screen only displayed weight data — no rate-of-change view existed. The user initially framed the request as wanting the 'second derivative.'

## Trigger

User requested a chart showing 'the rate of speed at which my weight is changing during the cut.' Assistant identified that this description matches the first derivative (velocity, lb/wk), not the second (acceleration). Design Q&A resolved: swipe between pages with dots; show both lb/wk and lb/day.

## Decision

Added a two-page swipeable TabView to the minichart: Page 1 = weight (unchanged), Page 2 = first derivative (rate of change). Rate page shows both lb/wk and lb/day readouts on one page, a dashed zero baseline, and omits the min/max/avg trend lines and target rule.

## Consequences

- Rate computed via central-difference of the already-5-day-smoothed weight line; endpoints use one-sided difference — avoids amplifying scale noise
- Shows 'Rate appears after a few days' placeholder when fewer than 2 smoothed points exist
- Both units displayed on one page rather than two near-identical per-unit pages
- Page-swipe gesture scoped to the chart TabView so it doesn't conflict with the day-to-day date swipe on the Today screen
- Only applied to the portrait minichart; the landscape focus chart still shows weight only

## Open Tail

- Landscape focus chart may need rate-page mirroring
- Second derivative (acceleration / plateau detection) could become a third page

## Evidence

- transcript lines 1-13
- transcript lines 160-164
- transcript lines 269-295

