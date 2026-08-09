# Today charts — canonical core plus focused lenses

Today keeps the canonical distinction between observation, trend, pace, plan,
and forecast while exposing the full set of focused visualizations the user
wants available. Progress vs Plan remains the cold-launch view; every other
chart is available in the carousel and can be reordered or hidden in Settings.

The exact formulas and civil-date semantics live in `docs/today-analytics.md`.

## Carousel order

1. **Progress vs Plan** — raw observations, seven-calendar-day trend, plan,
   target, today, and the fitted target-date forecast.
2. **Current Weight** — recent raw observations and the canonical trend.
3. **Total Lost** — cumulative change from the configured start weight.
4. **This Week** — observed change from the last reading before Monday.
5. **Week-to-Date Average** — Monday-based weekly means, current WTD mean, and
   observed min/max whiskers. The current comparison is matched by weekday.
6. **Recent Trend** — the current 14-calendar-day OLS fit and needed-now pace.
7. **Pace History** — historical rolling 14-day fits, restored as a diagnostic.
8. **Forecast** — the target-date endpoint and uncertainty from the current fit.
9. **Full Cut** — raw observations and trend across the active cut.
10. **Weekly Range** — weekly means with observed min/max variability.
11. **Week-over-Week Change** — bars of `current comparable weekly mean - prior
    comparable weekly mean`; falling means plot below zero.

## Presentation rules

- Raw observations and weekly aggregates use points and straight segments.
- The first real value on each chart is labeled just to the right of its point
  at the same y coordinate.
- Hero subtitles are intentionally narrow: date/window identity only. Reading
  counts do not appear beneath the headline.
- `trailing seven calendar days`, `Monday-based calendar week`, and `WTD` remain
  distinct labels and calculations.
- Weekly min/max whiskers are observed ranges, not confidence intervals.
- Week-over-week bars are changes in comparable weekly means, not directly
  measured fat loss.
- Falling weight is negative internally and shown with a down arrow in headline
  copy.

## Verification artifacts

- `Tests/TodayLensModelTests.swift` covers the Aug 2026 fixture and analytics
  edge cases.
- `Tests/TodayLensOrderTests.swift` verifies all 11 lenses, preference migration,
  straight geometry, concise subtitles, and first-point labels.
- `docs/today-lenses/` contains light/lb and dark/kg renderings of every lens.
