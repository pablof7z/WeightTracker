---
type: episode-card
date: 2026-06-17
session: 1a7ed5a0-cb16-4a32-8576-3fbf4e24310f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/1a7ed5a0-cb16-4a32-8576-3fbf4e24310f.jsonl
salience: product
status: active
subjects:
  - landscape-focus-chart
  - window-stats-card
  - gesture-navigation
supersedes:
  - 2026-06-17-1-landscape-focus-chart-contextual-stats-gesture
related_claims: []
source_lines:
  - 1-88
  - 153-182
captured_at: 2026-06-17T09:01:57Z
---

# Episode: Landscape chart adds window stats card and pan/pinch navigation

## Prior State

LandscapeFocusChart had only tap-to-inspect (vertical rule + value pill) and a preset window picker. No contextual stats for the visible window, and no gesture-based panning or span resizing.

## Trigger

User directive requesting: stats for the current window (start/end weight, delta total and %, projection display), a scrubber/gesture for sliding the window start through time, and pinch-to-resize the visible duration.

## Decision

Persistent top-left glass stats card showing window label, start→end weights, delta + percentage (~ suffix for projected values). DragGesture for panning (20pt minimum preserves tap-to-inspect), MagnificationGesture for span resize (3–180 days), pinch snaps to preset within 10% threshold. Picker dims to 45% opacity in custom mode as departure signal. Stats card dims to 30% during tap-inspect. Double-tap resets all state.

## Consequences

- Tap-to-inspect and gesture navigation coexist via .simultaneousGesture with minimum distance threshold
- Area fill path must extend to x=0 (screen edge), not start at the first data point, to avoid safe-area gaps — fixed and committed

## Open Tail

*(none)*

## Evidence

- transcript lines 1-88
- transcript lines 153-182

