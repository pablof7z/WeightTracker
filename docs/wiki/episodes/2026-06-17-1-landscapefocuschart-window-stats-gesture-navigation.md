---
type: episode-card
date: 2026-06-17
session: 1a7ed5a0-cb16-4a32-8576-3fbf4e24310f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/1a7ed5a0-cb16-4a32-8576-3fbf4e24310f.jsonl
salience: product
status: superseded
subjects:
  - landscape-focus-chart
  - chart-stats-card
  - gesture-navigation
supersedes: []
related_claims: []
source_lines:
  - 1-4
  - 83-88
  - 138-151
captured_at: 2026-06-17T08:41:48Z
---

# Episode: LandscapeFocusChart Window Stats & Gesture Navigation

## Prior State

LandscapeFocusChart had tap-to-inspect (vertical rule + value pill), a preset window selector, and double-tap-to-reset, but no contextual statistics for the visible window and no gesture-based timeframe navigation.

## Trigger

User requested window-aware stats (start weight, end weight, delta total and %, with projected values for future windows) and a scrubber/gesture system to pan and pinch across timeframes with clean UX.

## Decision

Added a persistent top-left glass stats card showing window label, start→end weights, delta in unit, and percentage; added DragGesture (20pt minimum distance) for horizontal pan and MagnificationGesture for span resize (3–180 days), with snap-to-preset within 10% threshold.

## Consequences

- Stats card dims to 30% opacity during tap-to-inspect so it doesn't compete with the selection pill
- Future-facing windows use the projection path for end value, displayed with ~ suffix
- Pinch snaps to nearest preset (7d/14d/30d) within 10% via spring animation
- Picker dims to 45% opacity in custom mode as a visual departure signal
- Tapping a preset pill resets pan offset and custom span; double-tap now resets everything (window, pan, span, selection)

## Open Tail

*(none)*

## Evidence

- transcript lines 1-4
- transcript lines 83-88
- transcript lines 138-151

