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
  - derivative-choice
supersedes:
  - 2026-06-17-1-rate-of-change-chart-added-as
related_claims: []
source_lines:
  - 1-13
  - 160-164
  - 182-297
  - 346-348
captured_at: 2026-06-17T08:27:30Z
---

# Episode: Minichart gains swipeable rate-of-change page (1st derivative, not 2nd)

## Prior State

The Today-screen minichart showed only weight over time — no rate-of-change view existed.

## Trigger

User requested a chart showing 'the rate of speed at which my weight is changing during the cut,' initially calling it the 'second derivative.'

## Decision

Added a swipeable two-page TabView inside ActiveCutMinichart: Page 1 is the existing weight chart (unchanged), Page 2 shows the first derivative (rate of change in lb/wk and lb/day). The assistant identified that what the user described — 'speed at which my weight is changing' — is the first derivative (velocity), not the second (acceleration), and built accordingly. Both time-unit readouts appear on one page rather than as separate pages. A dashed zero baseline and a 'Rate appears after a few days' placeholder handle the signed-value and sparse-data cases.

## Consequences

- Swipe gesture on the chart flips between Weight ↔ Rate pages; day-navigation swipe on the rest of Today screen is preserved via the TabView containment.
- Rate is computed via central-difference on the already-5-day-smoothed weight line to avoid amplifying scale noise; endpoints use one-sided difference.
- Both lb/wk and lb/day are shown in a single corner readout rather than as separate pages.
- Landscape focus chart (LandscapeFocusChart) was NOT updated — still only shows weight.
- Second derivative (acceleration/plateau view) is a potential future third page but was not implemented.

## Open Tail

- User posted a screenshot asking 'what's wrong' — visual/functional issue on device not yet diagnosed or resolved.
- Landscape focus chart does not yet mirror the rate page.
- Second-derivative page could be added as a third tab.

## Evidence

- transcript lines 1-13
- transcript lines 160-164
- transcript lines 182-297
- transcript lines 346-348

