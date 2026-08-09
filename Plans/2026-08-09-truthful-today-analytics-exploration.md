# Truthful Today analytics exploration

Date: 2026-08-09
Project/context: Cut Tracker iOS Today analytics and charts
Status: decided

## Core Question

- Which minimal set of mathematically defensible charts best explains current trend, recent change, plan, and likely outcome for an active cut?

## Current Working Model

- Canonical current trend: observed mean over the trailing seven civil calendar days ending on each observation date.
- Canonical recent pace: date-aware OLS through canonical raw observations over the latest 14-calendar-day window; no historical rolling-pace chart.
- Plan is the configured start-to-target line; required-now uses current trend and remaining civil days; forecast reuses the displayed OLS slope with an uncertainty interval.
- Today has three decision surfaces: Progress vs Plan; Recent Trend; Weekly Average + Observed Range.

## Observations

- The user supplied exact Aug 2026 acceptance values and explicitly requires an audit before implementation.
- The existing worktree already contains uncommitted Today backdrop/scrubbing, CSV import, tests, and snapshot updates on top of three local feature commits.
- Final acceptance includes installing and launching the merged app on the user's connected iPhone.

## Constraints And Invariants

- Raw weigh-ins are civil/local dates and missing days are not synthetic observations.
- Chart geometry must not invent extrema; raw and aggregated observations use points and straight segments.
- Plan, trend, recent pace, required-now pace, and forecast remain semantically and visually distinct.
- Falling weight uses a conventional negative mathematical slope internally and a consistent downward-loss presentation in UI.
- `Aug 2-Aug 8 trailing 7 days` and `week of Aug 3 (Monday-based)` are never conflated.
- Preserve the unrelated `.claude/worktrees` checkout as tooling state and do not commit it.

## Preferences

- Prefer simple, explainable estimators over sophistication.
- Prefer fewer, denser views: Progress vs Plan; Recent Trend/Pace; Weekly Average + Observed Range; separate Forecast only if independently useful.
- Use trend weight, not a single noisy observation, for required-now pace and forecast anchoring.

## Assumptions

- `WeightTracker` is the intended iOS scheme; verify with project discovery and tests.
- The currently tracked snapshot changes belong to the Today work; verify their relationship to the implementation before committing.

## Open Questions

- Verify the physical-device data migration for the new optional civil-day key on the user's installed store.
- Calibrate the forecast uncertainty-width gate from test and live fixture output; omit rather than overstate when too wide.

## Hypotheses

- An optional persisted civil-day key supports lightweight migration while making all new readings timezone-stable; existing nil keys require a legacy fallback.

## Risks

- Reusing current terminology could preserve semantic contradictions after formulas change.
- Sparse or duplicated same-day observations can overweight particular civil dates unless daily aggregation is explicit.
- A broad UI rewrite can regress the already-modified Today interaction and backdrop behavior.
- Project files may need regeneration if sources/tests are added.

## Evidence Gathered

- User acceptance fixture and desired hierarchy in the 2026-08-09 prompt.
- Git status and history: `today-masked-decorative-background` is three commits ahead of `master` with 26 tracked files modified.
- XcodeBuildMCP scheme discovery lists `WeightTracker`, `WeightTrackerWatch`, `VoiceCaptureKit`, and `ShakeFeedbackKit`.
- `docs/today-analytics.md` records the full formula/window/semantics audit and final definitions.

## Adjacent Checks

- Adjacent check: Can the current analytics ownership boundaries support one canonical estimator without duplicating logic?
  Finding: Today currently consumes four incompatible level/anchor models: a trailing calendar mean, a seven-reading EMA, an interpolated alpha-0.10 EWMA, and a trimmed seven-reading forecast anchor.
  Implication: Today needs a dedicated canonical analytics model; unrelated deeper estimators can remain isolated.
  Confidence: high

## Alternatives Considered

- Trailing seven readings: responsive but treats irregular observation cadence as regular time and can span arbitrarily long periods.
- EWMA: responsive and recursive but less transparent to users and fixture interpretation.
- Historical rolling-pace chart: may reveal genuine changes, but differentiates noisy estimates and can amplify window-edge artifacts.

## Rejected Options

- Decorative spline interpolation for raw or weekly measurements: rejected because it can invent unobserved extrema.
- Calling a planned value a projection: rejected because plan and forecast are different quantities.
- Treating trailing seven days and a calendar week as interchangeable: explicitly rejected by the user.

## Decisions Or Emerging Direction

- Audit every current metric and chart before editing implementation.
- Implement the reduced model, add fixture and edge-case regression coverage, merge to `master`, then run the merged app on the connected iPhone.
- Persist civil-day identity for new readings and reconstruct it in the analysis calendar.
- Remove Catmull-Rom smoothing from observation, trend, plan, forecast, and weekly lines.

## Follow-Up Artifacts

- Canonical audit and formulas: `docs/today-analytics.md`.
