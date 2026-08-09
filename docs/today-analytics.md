# Today analytics: audit and canonical model

Date: 2026-08-09

## Product question

Today should answer: given noisy daily weigh-ins, what is the underlying weight trend, how fast is it changing, how does it compare with the configured cut, and what does that imply for the target date?

The canonical order is:

`civil-date observations -> current trend level -> recent fitted rate -> configured plan -> forecast`

Each quantity keeps its own name. A raw reading is not a trend. Planned weight is not a forecast. A difference between weekly means is not the recent regression pace.

## Existing implementation audit

### Shared input

- `CanonicalDailyWeightSeries.prepare` groups readings by `Calendar.startOfDay`, from an optional inclusive start through an optional inclusive end.
- If a civil day has manual readings, non-manual readings are ignored and the manual values are averaged. Otherwise all values for the day are averaged.
- Missing days are omitted; they are not zero-filled or duplicated.
- Risk: `Reading` stores only a `Date` instant normalized in the timezone active at insertion. Re-bucketing that instant in a different timezone can change the apparent day. CSV parses `yyyy-MM-dd` in UTC and then normalizes it with the current calendar, which can shift dates west of UTC.

### Current Weight lens

- Headline: the raw reading for the selected day. If that day is unlogged, the UI carries a prior raw value forward as a muted placeholder; on today it gives no textual last-recorded date.
- Plot: canonical raw readings over roughly 30 calendar days plus a trailing seven-calendar-day observed mean.
- Trend formula at observation date `d`: arithmetic mean of canonical observations whose civil dates are in `[d - 6 days, d]`. The window is calendar-time based and missing dates contribute nothing.
- Supporting figures: latest trailing-seven mean; current calendar-week endpoint change; target-date value from `CutProjection`.
- Problems: the primary signal is raw weight; an unlogged day is not explicit enough; the three supporting values mix trend, a noisy endpoint difference, and a forecast from a different anchor.

### Total Lost lens

- Headline and plot: `configured start weight - raw observation`.
- This is an affine restatement of the main weight series. It is useful as a supporting value, not an independent chart.

### This Week lens

- Monday-Sunday calendar week.
- Baseline: last canonical reading before Monday, or the first in-week reading when none exists.
- Each plotted value: `raw in-week reading - baseline`.
- Headline: final plotted endpoint difference. Average/day divides that endpoint difference by elapsed calendar days through the final reading.
- Problems: it treats two noisy endpoints as a weekly signal and is not a weekly average. It is mathematically defined but too noisy and easily confused with weekly-mean change.

### Weekly Average lens

- Monday-Sunday buckets; partial cut-boundary weeks are marked partial and week-to-date is explicit.
- Mean/min/max use canonical observations only. Missing days do not contribute.
- Full-week comparison: prior weekly mean minus current weekly mean, positive for loss.
- Week-to-date comparison: current observed weekdays are compared with the prior week truncated to the same weekday. The current and previous periods may still have different reading coverage.
- Planned average: mean planned weight on the dates actually observed that week.
- This aggregation is useful, but its separate average and range lenses duplicate one another.

### Pace lens

- At each canonical observation date, fit ordinary least squares to raw canonical weights in the inclusive trailing 14-calendar-day window.
- Minimum: three observations spanning at least three calendar days.
- Internal slope: pounds/day, negative while weight falls. Display converts it to positive loss magnitude with `-slope * 7`.
- The lens plots the entire history of rolling 14-day slopes over the last 30 days.
- `requiredConstant`: `(start - target) / total cut weeks`.
- `requiredNow`: `(projection anchor - target) / remaining weeks`, clamped to zero when target is reached or no days remain.
- Problems: the rolling slope history is a noisy derivative chart; `requiredNow` uses the forecast engine's trimmed-reading anchor rather than the displayed seven-day trend; the UI labels both plan concepts as required in different places.

### Forecast lens

- Anchor: `CutProjection` uses the last seven in-cut reading objects, drops one minimum and one maximum, and averages the remainder; with fewer than three it uses the latest reading.
- The anchor is reading-count based rather than calendar-window based and does not first canonicalize duplicates.
- Best/typical/worst rates come from prior detected cuts in percent body weight per week; cold start uses fixed priors of -1.0%, -0.7%, and -0.3% body weight/week.
- Typical path adds a deterministic circular block bootstrap of residuals from up to two historical cuts; best/worst are straight rays. All paths are floor-capped.
- Dates use repeated 86,400-second steps and raw timestamp differences, which are not civil-date/DST safe.
- Problems: the model is independent of the displayed recent pace and current trend, so its result need not be mathematically compatible with either. The historical-cut model may remain useful elsewhere, but Today cannot present it as if it followed from the current evidence shown on screen.

### Full Cut lens

- Raw readings and the trailing-seven mean over the fixed start-to-target domain, plus a target line.
- Useful time context, but it omits the configured planned trajectory and duplicates Current Weight/Total Lost.

### Weekly Range lens

- Same weekly means as Weekly Average plus observed min/max whiskers.
- This is the useful superset of Weekly Average. The min/max is an observed range, not uncertainty.

### Weekly Loss lens

- Bars of `previous comparable weekly mean - current weekly mean`, positive for loss, against original planned weekly loss.
- This is the first difference of the weekly-mean series and largely repeats information visible in Weekly Average + Range while amplifying oscillation.

### Other analytics still present in the app

- `TodayViewModel.computeEMA7Kg`: EMA with alpha 0.25 over the latest seven reading objects, not seven calendar days and not canonical daily values. It appears in the log sheet as “7-day avg.”
- `CutDeficitEstimator`: linearly fills missing calendar days, applies an alpha-0.10 EWMA, then fits a 14-day OLS slope to that interpolated trend. This is a distinct model used to estimate caloric deficit.
- `CutWeightProjector`: anchors on the alpha-0.25 seven-reading EMA, takes its slope from the alpha-0.10 interpolated EWMA, phase-adjusts it, and applies a 320-day exponential approach with a propagated slope-error band.
- These models may serve their own deeper features, but they must not silently define Today’s trend or pace.

## Errors versus presentation problems

Mathematical/data errors:

- Stored dates do not retain an explicit civil-day identity, so timezone changes can reclassify a reading.
- CSV civil dates are parsed as UTC instants and then normalized in the current timezone.
- Catmull-Rom drawing can overshoot raw and weekly observations and visually invent extrema.
- `requiredNow` is calculated from a different anchor than the displayed trend.
- Forecast civil-day arithmetic uses fixed 86,400-second increments.

Mathematically defined but misleading or unhelpful:

- The raw/placeholder Current Weight headline is visually primary over trend.
- Historical rolling-pace curves amplify window-edge noise.
- This Week is a difference of noisy endpoints.
- Total Lost and Full Cut are transforms/subsets of one Progress vs Plan chart.
- Weekly Average and Weekly Range are duplicate views.
- Weekly Loss is a derivative of the weekly-average view.
- “Projection,” “Required,” and “Pace” labels cover multiple incompatible quantities.

## Canonical definitions

### Civil day and canonical observation

- New readings persist an explicit `yyyy-MM-dd` civil-day key alongside the storage `Date`.
- Analytics reconstruct that civil day in the requested calendar/timezone. Existing records without a key retain the legacy date fallback.
- One canonical observation per civil day: manual source wins; ties are averaged. Missing days remain missing.

### Current trend

- At each observed civil day `d`, current trend is the arithmetic mean of canonical observations in `[d - 6 calendar days, d]`.
- The headline uses the latest available trend point. It states the trailing-calendar window and reading count.
- The latest raw observation is separately labeled with its civil date. If no reading exists today, the UI says `Latest: value · date`; it never implies that value was measured today.
- Rationale: this is calendar-aware, directly explainable, robust to one noisy day, and does not invent missing measurements. A reading-count EMA was rejected because irregular logging changes its effective time horizon.

### Recent pace

- Fit date-aware ordinary least squares through canonical raw observations in the 14-calendar-day window ending on the latest observation date.
- Require at least three observations spanning at least seven calendar days; otherwise report insufficient data.
- Internal slope is signed weight change per day. UI presentation is `down` for a negative slope and `up` for a positive slope, always including `14-day fit` and the observation count.
- Rationale: OLS estimates a local linear trend directly from noisy observations. It does not differentiate a rolling mean, so it is less vulnerable to the large edge artifacts of a historical rolling-pace curve. No historical pace curve remains on Today.

### Plan

- Planned trajectory is the configured straight line from `(start date, start weight)` to `(target date, target weight)`.
- `planned weight today` is that line evaluated on today's civil date, clamped to the configured interval. It is never called a projection.
- Original planned pace is `(start weight - target weight) / total cut weeks`.

### Required now

- If the current trend is already at/below target, needed-now pace is zero and the state is goal reached.
- If the deadline is today/past while trend remains above target, the state is deadline passed and no finite needed-now pace is shown.
- Otherwise: `(current trend - target weight) / remaining weeks from today's civil date`.
- It uses current trend, never a single reading or an unrelated forecast anchor.

### Forecast

- Today uses a transparent target-date forecast derived from the same 14-day OLS pace displayed on Recent Trend.
- It begins at the current trend on today's civil date and extends linearly to the target date.
- The interval propagates OLS slope uncertainty to the target date. It is labeled as a fitted-trend forecast, not a plan.
- It is omitted when the fit is unavailable, the deadline has passed, or the uncertainty is too wide to be useful. The historical-cut/bootstrap and physiology projector remain separate deeper models, not silent inputs to this Today number.

### Weekly average + observed range

- Monday-Sunday civil calendar weeks.
- Mean, minimum, maximum, and reading count use only observed canonical days.
- The current week is labeled WTD. Comparison uses the prior week through the same weekday and is labeled provisional/matched-period.
- Min/max is always called observed range.

## Today information architecture

1. **Progress vs Plan**
   - Question: where is the trend, how does it compare with the configured cut, and where does the current fitted rate point by the deadline?
   - Plot: raw points; straight-segment seven-calendar-day trend; configured plan; today; target; optional forecast and uncertainty interval; numeric date and weight references.
2. **Recent Trend**
   - Question: is the recent evidence actually moving down, and is that fitted pace enough from here?
   - Plot: recent raw points; straight-segment trend; straight OLS fit. Supporting values: recent pace, needed now, original plan.
3. **Week-to-Date Average**
   - Question: are weekly levels moving despite daily noise, and how much observed variability/coverage is behind each mean?
   - Plot: Monday-based means joined with straight segments; observed min/max whiskers; reading counts and explicit WTD state.

The canonical three decision views remain the primary model. Following direct
product feedback, focused Current Weight, Total Lost, This Week, Pace History,
Forecast, Full Cut, Weekly Range, and Week-over-Week Change lenses are also
available. They consume the same canonical observations and definitions rather
than redefining trend, pace, plan, or forecast. Pace History and Week-over-Week
Change are explicitly diagnostic/noisy derivative views, not the primary basis
for a decision.

## Acceptance fixture

The Aug 2026 fixture must distinguish:

- trailing seven days Aug 2-8: six readings, mean 153.6167 lb, observed range 152.8-154.8 lb;
- Monday-based week of Aug 3 through Aug 8: five readings, mean 153.38 lb, observed range 152.8-153.7 lb;
- Jul 26-Aug 8 date-aware raw OLS pace: approximately down 1.184 lb/week;
- Aug 9 planned weight: approximately 152.56 lb;
- current trend versus plan: approximately 1.06 lb above plan;
- needed from a 153.6167 lb trend on Aug 9 to 150 lb on Aug 21: approximately down 2.11 lb/week.

Tests also cover missing days, duplicate source resolution, sparse data, timezone/DST reconstruction, goal reached, deadline passed, short horizons, water spikes/outliers, flat/gaining trends, and changed target/deadline inputs.
