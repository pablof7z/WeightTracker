# Today redesign — three decision views

Today is a compact set of three mathematically distinct views. The surface is
organized around the question: what is the underlying weight trend, how is it
changing, how does it compare with the configured cut, and what does that imply
for the target date?

The exact formulas, date semantics, previous implementation audit, and
acceptance fixture live in `docs/today-analytics.md`.

## The three views

1. **Progress vs Plan** — the whole active cut on one coordinate system: raw
   observations, trailing-seven-calendar-day trend, configured start-to-target
   plan, today, target, and an optional target-date fitted-trend forecast with an
   uncertainty interval.
2. **Recent Trend** — a recent zoom of raw observations and the canonical trend,
   plus one straight 14-calendar-day OLS fit. The headline is the recent rate;
   supporting values separate needed-now pace, original planned pace, and the
   current trend level.
3. **Weekly Average + Range** — Monday-Sunday observed means, straight connecting
   segments, observed min/max whiskers, reading coverage, and explicit WTD
   treatment. A partial current week compares with the prior week through the
   same weekday.

Progress vs Plan is always the launch view. Old saved carousel preferences are
migrated to the new identifiers and an empty selection falls back to Progress.

## What was merged or removed

- Raw Current Weight, Total Lost, and Full Cut were merged into Progress vs Plan.
- The separate Forecast page was integrated into Progress vs Plan because it
  uses the same displayed recent fit and target-date question.
- This Week endpoint change and historical rolling Pace were removed from Today;
  both overemphasized noisy derivatives.
- Weekly Average and Weekly Range were merged into their useful superset.
- Weekly Loss bars were removed because they were the first difference of the
  weekly-mean series and repeated information less clearly.

The historical-cut bootstrap forecast, physiology projector, and deficit EWMA
remain separate deeper analyses. They do not silently define Today's trend,
recent pace, or forecast.

## Chart truthfulness

- Weight-entry identity is an explicit civil-day key; missing dates are never
  filled, duplicated, or zeroed.
- `trailing seven calendar days` and `Monday-based calendar week` are separate
  windows and are labeled separately.
- Raw readings are points. Trend, plan, fit, forecast, and weekly means use
  straight segments. The renderer does not apply decorative curve smoothing.
- The y domain includes stable numeric references and the cut context so small
  fluctuations are not made to look enormous.
- Plan and forecast are different line styles and labels. Needed-now pace uses
  current trend, not the latest raw reading or a different forecast anchor.
- Falling weight is a negative internal slope and a consistent `down` loss rate
  in presentation.

## Logging and interaction

- Tap the hero value to toggle lb/kg; long-press opens weight entry.
- If today is unlogged, `Log today` is explicit while the latest recorded value
  retains its own civil date.
- Hold and move across a chart to inspect points without changing stored data.
- Tap a chart to open the deeper detail view.

## Verification artifacts

- `Tests/TodayLensModelTests.swift` covers the Aug 2026 acceptance fixture,
  missing days, duplicates, timezones/DST, sparse samples, goal/deadline edges,
  spikes/outliers, flat trend, gain, and changed goal inputs.
- `Tests/TodayLensOrderTests.swift` verifies the reduced view order, preference
  migration, semantics, and straight-line geometry.
- `docs/today-lenses/` contains light/lb and dark/kg renderings of all three
  retained views.
