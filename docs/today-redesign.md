# Today redesign — the lens carousel

The Today tab is now a horizontally paged set of six **lenses**, each a single
mathematical perspective on the active cut. Data leads; there are no verdicts,
smileys, or motivational copy. One primary number, one full-bleed visual
explanation, three supporting figures.

## The six lenses (fixed order)

1. **Current Weight** — latest canonical daily reading; 30-day history + 14-day
   forecast tail; supporting: 7-day avg, this-week change, projection.
2. **Total Lost** — `start − latest`, charted as cumulative loss from zero over
   the fixed cut window against the goal-loss reference.
3. **This Week** — signed cumulative change Mon–Sun vs the last pre-week reading
   (partial if none); fixed ±4 range around zero; sign and chart always agree.
4. **Weekly Average** — last 8 completed weeks + the current week-to-date point
   (hollow), matched-weekday comparison for the change figure.
5. **Pace** — a genuine rate in lb/week from a trailing 14-day, date-aware
   least-squares regression, against the required-now reference and zero.
6. **Forecast** — recent history into the shared anchor, then a typical line and
   a lower/upper band over the final 60 days to target.

The first lens on every launch is Current Weight; the selection is retained for
the session but never persisted, so a secondary lens can't become the default.

## What was consolidated / removed

- **Old Today carousel** (`ActiveCutMinichart` + `StableCutChart` variation
  pages: absolute weight, pounds-remaining, goal-completion %, cumulative loss,
  ahead/behind pace, plus four weekly modes) is no longer the Today surface.
  Those are affine restatements of Current Weight / Total Lost, a supporting
  figure inside Pace, or content for the deeper weekly screen. `StableCutChart`
  and `LandscapeFocusChart` are retained only for the tap-through / landscape
  **detail** chart, which reuses the exact same prepared `CutChartModel`.
- **Stacked Today widgets removed from the canvas**: the cut progress strip +
  milestone markers, `CutDeficitWidget`, and the `WeightForecastWidget`. The
  forecast is now the Forecast lens; the deficit belongs in Insights (it is
  largely a linear transform of trend loss); milestones remain elsewhere in the
  app (Cuts, coach) but no longer crowd Today.
- **Horizontal date-swipe gesture deleted.** Horizontal swiping now has one
  unambiguous meaning — changing lenses. Date navigation lives entirely in the
  title / date-picker control.

## What was corrected

- **Pace is now a rate.** The previous "rate" page overlaid a normalized weight
  curve on a rate axis. The new Pace lens plots lb/week from a trailing,
  date-aware regression (positive = losing), never a differentiated daily
  reading and never a centered window that peeks at the future.
- **This Week is new and sign-correct.** Cumulative change within the calendar
  week against a documented baseline; the headline equals the final charted
  point exactly.
- **Full-bleed charts with shared geometry.** A custom `LensPlot` (`Canvas`, not
  Swift Charts) generates the line and its area fill from *one* path generator,
  so the fill boundary can never diverge from the line. Fills are gradients
  anchored to the full plot rectangle — no `AreaMark` bounding-box slab, no
  left y-axis gutter, no chart card. At most two–three in-canvas date labels.
- **Shared pipeline preserved and reused.** All lenses consume the existing
  canonical daily series (one value per day, manual wins), the trailing 7-day
  trend (adding tomorrow never rewrites yesterday), the single shared forecast
  anchor, and the persisted stable domains.

## Logging & interaction

- Tap the hero number → toggle lb ↔ kg. Long-press → the normal decimal keyboard
  (`LogWeightSheet`), routed through the existing save pipeline (HealthKit,
  coach, notifications unchanged). A "Log today" affordance appears when there is
  no reading for today.
- A deliberate tap on any chart opens the deeper landscape detail chart.
- Restrained page dots, a one-time swipe hint, and a settle haptic. Reduce
  Transparency swaps the glass shelf for an opaque accessible surface; each lens
  exposes a concise VoiceOver summary (name, headline, horizon, three figures).

## Deferred (explicitly, per plan)

- **Photo motivation backdrop** (optional presentation layer).
- **Deeper-chart upgrades** beyond reusing the current landscape focus chart
  (point inspection, pan/pinch, raw-vs-trend toggles).

## Files

- `Sources/Shared/Analysis/TodayLensModel.swift` — `TodayLens`, `PaceLensModel`,
  `ThisWeekModel` (pure, unit-tested).
- `Sources/iOS/Features/Today/LensPlot.swift` — full-bleed plot renderer.
- `Sources/iOS/Features/Today/TodayLensCarousel.swift` — carousel + shared
  hero/shelf composition + previews.
- `Sources/iOS/Features/Today/TodayLensBuilder.swift` — per-lens content.
- `Sources/iOS/Features/Today/TodayLensSupport.swift` — log sheet + detail cover.
- `Tests/TodayLensModelTests.swift` — pace/this-week/hero acceptance tests.
- `Tests/TodayLensSnapshotTests.swift` — exports `docs/today-lenses/*.png`.
