# Today lens — visual refinement brief (historical)

> Superseded on 2026-08-09 by `today-redesign.md` and
> `today-analytics.md`. This file records the preceding six-view visual design;
> it is not the current analytics or information architecture specification.

Goal: rebuild the Today lens as ONE continuous, immersive, data-first canvas that
matches the Current-Weight-First prototype. This is a composition/rendering/visual
pass, NOT new features. Preserve all live, mathematically-correct data — do not
change numbers to match the prototype. Sequenced to run AFTER the nav restructure
(tab bar removal), because §11 depends on the final navigation.

## 1. One continuous canvas
Two softly-connected zones: (1) quiet upper hero, (2) full-bleed visualization that
continues to the bottom edge. Chart background transitions from the light hero into a
saturated accent gradient (or photo). Canvas continues BEHIND date labels, supporting
figures, page dots, and the bottom navigation glass. No rounded container around the
chart or the metrics. No opaque white between chart and nav. No stacked bottom pills.

## 2. Remove redundancy
No Day+date twice. Prefer: nav title = "Today"; below hero value show "Jul 19, 2026 ·
Day 84". Remove/greatly reduce the "CURRENT WEIGHT" heading — the value is self-
explanatory. No verdict copy.

## 3. Hero composition (centered)
Center the primary value horizontally. Hierarchy: Today nav title → hero value → date+
cut day → tiny page dots → optional one-time "Swipe for more" → full-bleed chart.
Hero block ≈ upper 28–32% of usable screen (not ~half). Bring the chart UP; kill the
dead band. Type: hero ≈84–96pt bold/black rounded; unit baseline-aligned ≈26–30pt;
date 15–17pt regular; metric labels 11–12pt; metric values ≈23–27pt monospaced.
Monospaced digits for all changing measurements.

## 4. Chart must feel designed (cool-blue system for Current Weight)
Atmospheric DEPTH gradient, not a flat fill: top very pale cool blue → mid medium
desaturated blue → bottom deep navy. Primary line white/near-white. Secondary series
low-opacity white/accent. Projection restrained white dashed. Text over the lower
canvas is white with controlled opacity. Do NOT use default system blue as the whole
palette.

## 5. One dominant signal
Only one series dominant. Canonical daily is the factual data; trailing trend is
secondary (≈15–30% opacity / thinner / restrained points) — no competing second bright
curve. The chart must make clear which endpoint is the headline reading.

## 6. Full-bleed plot geometry
Canvas reaches both screen edges. No left y-gutter, no external y labels, no horizontal
card padding. Small internal safety inset only (must not read as a margin). 2–3 date
labels inside the canvas near the lower edge. Chart occupies ≈55–65% of screen height
INCLUDING the regions behind metrics and nav.

## 7. Area under the line (two layers)
(A) Full-canvas background gradient/photo, independent of line geometry, extends through
the lower screen. (B) A mathematically-bounded area under the line: subtle extra shading
clipped to the line, strongest just below it, fading to transparent — does NOT replace
the background and does NOT fade into a white page or a pale rectangle. Plain bg: area
≈15–25% near line → 0% deep. Photo bg: ≈8–15%. Fill and stroke MUST share identical
points + interpolation. Build the fill in plot coordinates; clip a gradient spanning the
full visible plot (no AreaMark bbox compression). Atmospheric, not a polygon.

## 8. Endpoint + forecast
Restrained current marker: small inner point + thin ring + optional subtle halo — no
oversized bubble. Projection begins exactly at its real anchor, matches the series it
continues, shorter refined dash, lower contrast, never disconnected. STRONGLY prefer
REMOVING the projection tail from Current Weight (Forecast lens owns projection) so
Current Weight shows observed data only. Never a dashed forecast floating away from the
emphasized current marker.

## 9. Supporting metrics are NOT a card
Remove the rounded stats card. Render the three values directly over the darker lower
chart: small secondary labels, large monospaced values, thin low-opacity vertical
separators, ≈20–24pt horizontal inset. No rounded rect, no shadow, no white background.
They should feel part of the chart.

## 10. Page indicator
Move dots into the composition (between hero metadata and chart, or just above the
metrics). Small conventional dots — not a long blue capsule. "Swipe for more" is a
one-time affordance; after first page, dots suffice.

## 11. Bottom navigation (POST tab-bar-removal)
The nav restructure removes the bottom tab bar; the continuous canvas must run to the
bottom edge behind any remaining glass controls. Any remaining nav/controls: low
opacity, minimal tint/shadow, no nested selected pill, legible, respect Reduce
Transparency. Glass = controls, not a container around the visualization. Top settings/
mic glass can be slightly smaller/quieter.

## 12. Optional personal photo backdrop (implement as optional mode)
User picks a collection of climbing photos. Per daily image: aspect-fill the canvas;
monochromatic overlay from the active lens accent; soft light scrim behind the hero;
darker bottom vignette behind dates/metrics/nav; preserve photo detail through center;
chart line stays legible (white + subtle dark halo). Deterministic one-per-day rotation
(not per redraw); same daily photo across all lenses. Default fallback = the atmospheric
blue gradient, still intentional.

## 13. Vertical rhythm (proportions, not hardcoded)
≈8–10% chrome / 18–22% hero / 5% pager cue / 50–55% visualization / 12–15% metrics over
the viz / nav over the continuing canvas. Chart starts substantially higher; lower canvas
continuous.

## 14. Motion
Paging = movement through views of the same data. Hero number crossfade/subtle numeric
transition; curve crossfade/morph; background tint/image spatially stable across pages;
supporting values crossfade; very light settle haptic. No bouncing cards / big springs.

## 15. Acceptance — FAILS if any remain
stats in a floating white card · chart ends before stats/nav · white gaps between chart/
metrics/pager/nav · chart looks like default Swift Charts · two series compete equally ·
projection not originating from its endpoint · date/day repeated · several unrelated
rounded rects · hero and chart feel separate · photo looks like wallpaper behind cards ·
fill and line geometry diverge · visible left y-gutter · nav more prominent than chart.
SUCCEEDS when it reads as: one number / one continuous curve / one immersive canvas /
three supporting facts / one quiet swipe cue. Same visual family as the prototype.

Apply the same continuous-canvas system to all six lenses (each keeps its categorical
accent); Current Weight is the reference implementation.
