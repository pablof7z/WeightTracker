---
type: episode-card
date: 2026-06-17
session: 1a7ed5a0-cb16-4a32-8576-3fbf4e24310f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/1a7ed5a0-cb16-4a32-8576-3fbf4e24310f.jsonl
salience: product
status: superseded
subjects:
  - landscape-focus-chart
  - chart-stats-panel
  - chart-gesture-nav
supersedes:
  - 2026-06-17-1-landscapefocuschart-window-stats-gesture-navigation
related_claims: []
source_lines:
  - 1-152
captured_at: 2026-06-17T08:55:50Z
---

# Episode: Landscape Focus Chart: Contextual Stats & Gesture Navigation

## Prior State

LandscapeFocusChart had a window selector but no stats panel showing start/end/delta for the visible window, and no gesture-based navigation to pan through time or resize the duration.

## Trigger

User requested: (1) contextual statistics for the current visualization window (start weight, end weight, delta total and %), with projected values when window includes the future; (2) a scrubber/gesture UX for sliding the window through time and resizing duration via pinch.

## Decision

Top-left persistent glass card showing window label, start→end weights, delta (absolute + %); future-facing windows show projected end values with ~ suffix. Drag gesture (20pt minimum distance) pans the window through time; MagnificationGesture resizes duration (3–180 days) with snap-to-preset within 10%; picker dims to 45% in custom mode; double-tap resets all state.

## Consequences

- Stats card dims to 30% opacity during tap-to-inspect to avoid visual competition
- 20pt minimum gesture distance preserves tap-to-inspect without conflict
- Pinch direction matches map convention (pinch-in = shorter span)
- Preset snap uses spring animation for tactile feedback

## Open Tail

*(none)*

## Evidence

- transcript lines 1-152

