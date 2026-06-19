# Wiki Index

> Derived cache — do not hand-edit. Rebuilt by proactive-context after each capture.

Last updated: 2026-06-17

## coach-interaction (4 guides)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [coach-agent-session](coach-agent-session.md) | Coach Agent Session | The `CoachAgentSession.finishSucceeded()` auto-save mode is changed to `auditOnly`. | capture | warm | 2026-05-11 | coach-interaction |
| [coach-conversation-thread](coach-conversation-thread.md) | Coach Conversation Thread | All coach interactionsâcheck-ins, proposals, observations, and coach-initiated messagesâare unified into a single persistent thread, replacing the previous | capture | warm | 2026-05-11 | coach-interaction |
| [coach-proactive-nudges](coach-proactive-nudges.md) | Coach Proactive Nudges | Proactive coaching should dominate interactions, with roughly 80% of interactions coach-initiated rather than reactive | capture | warm | 2026-05-11 | coach-interaction |
| [watch-companion-tts](watch-companion-tts.md) | Watch Companion and TTS | A Watch companion with TTS audio output is the highest-value missing feature for future implementation. | capture | warm | 2026-05-11 | coach-interaction |

## docs-and-onboarding (4 guides)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [marketing-website](marketing-website.md) | Marketing Website | The marketing website is deployed to cut.f7z.io | capture | warm | 2026-06-14 | docs-and-onboarding |
| [readme-and-onboarding](readme-and-onboarding.md) | README and Onboarding | The README focuses on getting people excited about the app rather than explaining technicals, and uses screenshots to explain features | capture | warm | 2026-06-13 | docs-and-onboarding |
| [testflight-builds](testflight-builds.md) | TestFlight Builds | The build number for the TestFlight upload containing this fix is 202605151030. | capture | warm | 2026-05-15 | docs-and-onboarding |
| [workflow-conventions](workflow-conventions.md) | Workflow Conventions | Implementations must commit and push when done. | capture | warm | 2026-05-15 | docs-and-onboarding |

## feedback-system (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [feedback-integration](feedback-integration.md) | Feedback Integration | SharedFeedbackIntegration.swift wires ShakeFeedbackKit to FeedbackService. | capture | warm | 2026-06-13 | feedback-system |

## healthkit-data-sync (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [healthkit-data-sync](healthkit-data-sync.md) | HealthKit Data Sync | Re-importing activity data from Apple Health overwrites existing data for those days before inserting fresh records, except that manually-entered readings (sour | capture | warm | 2026-05-11 | healthkit-data-sync |

## secrets-management (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [secrets-and-repo-hygiene](secrets-and-repo-hygiene.md) | Secrets and Repo Hygiene | The repository is publicly accessible at https://github.com/pablof7z/WeightTracker | capture | warm | 2026-06-13 | secrets-management |

## skills (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [claude-skills-system](claude-skills-system.md) | Claude Skills System | Personal (user-level) skills are stored as directories under `~/.claude/skills/<skill-name>/` and are available across all projects | capture | warm | 2026-05-04 | skills |

## ui-components (7 guides)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [chart-interaction-gestures](chart-interaction-gestures.md) | Chart Interaction Gestures | FullscreenChart.swift and all tap-to-fullscreen gestures across 5 views have been removed, replaced with a landscape rotation hint. | capture | warm | 2026-06-13 | ui-components |
| [minichart-data-refresh](minichart-data-refresh.md) | Minichart Data Refresh | Minichart data refreshes after weigh-in without requiring a restart, including animation | capture | warm | 2026-06-13 | ui-components |
| [rate-page-visualization](rate-page-visualization.md) | Rate Page Visualization | The Rate page visualizes the first derivative of weight (velocity in lb/wk and lb/day), not the second derivative (acceleration) | capture | warm | 2026-06-17 | ui-components |
| [settings-view-navigation](settings-view-navigation.md) | Settings View Navigation | The settings button is located on the top-right of the tab bar (specifically Today's top-right toolbar) and opens SettingsView as a sheet; the standalone Settin | capture | warm | 2026-05-11 | ui-components |
| [swift-concurrency-interop](swift-concurrency-interop.md) | Swift Concurrency Interop | The ISO8601DateFormatter static property uses nonisolated(unsafe) to satisfy Swift 6 concurrency requirements. | capture | warm | 2026-05-11 | ui-components |
| [weight-chart-visualization](weight-chart-visualization.md) | Weight Chart Visualization | The gradient fill area path (areaFillPath) must use the same smoothed line data as the chart line to avoid visual mismatch between the line and its fill | capture | warm | 2026-06-13 | ui-components |
| [whats-new-feature](whats-new-feature.md) | What's New Feature | The What's New feature informs users about recent changes | capture | warm | 2026-05-15 | ui-components |

## workflow-conventions (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [session-responsibilities](session-responsibilities.md) | Session Responsibilities | The session does not include publishing tweets or writing content; that work belongs to a separate session (ea973f) on the fabric. | capture | warm | 2026-06-17 | workflow-conventions |

## writer-agent (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [writer-agent](writer-agent.md) | Writer Agent | The writer agent is defined in ~/.tenex/edge/agents-definition/writer.json | capture | warm | 2026-06-17 | writer-agent |

## Research Records (2 records)

| Record | Date | Finding | Agent |
|--------|------|---------|-------|
| [2026-06-17-1-independent-verification-of-rate-of-change](research/2026-06-17-1-independent-verification-of-rate-of-change.md) | 2026-06-17 | Independent verification of rate-of-change math against raw iPhone weight data; verdict: calculation correct at −1.9 lb/wk, but discovered duplicate-readings storage bug (40/50 days have DST-induced duplicates) | main |
| [2026-06-17-1-verification-of-rate-of-change-calculation](research/2026-06-17-1-verification-of-rate-of-change-calculation.md) | 2026-06-17 | Verification of rate-of-change calculation correctness and discovery of duplicate-readings data bug, with cross-validation against ground truth | main |

## Episode Cards (19 cards)

| Card | Date | Title | Salience | Status |
|------|------|-------|----------|--------|
| [2026-06-13-1-internal-planning-docs-excluded-from-public](episodes/2026-06-13-1-internal-planning-docs-excluded-from-public.md) | 2026-06-13 | Internal planning docs excluded from public repo | architecture | active |
| [2026-06-13-1-weight-chart-line-switched-from-raw](episodes/2026-06-13-1-weight-chart-line-switched-from-raw.md) | 2026-06-13 | Weight chart line switched from raw readings to EWMA smooth line | root-cause | superseded |
| [2026-06-14-1-fullscreen-chart-modal-replaced-by-landscape](episodes/2026-06-14-1-fullscreen-chart-modal-replaced-by-landscape.md) | 2026-06-14 | Fullscreen chart modal replaced by landscape rotation | product | active |
| [2026-06-14-1-weight-chart-line-rendering-raw-readings](episodes/2026-06-14-1-weight-chart-line-rendering-raw-readings.md) | 2026-06-14 | Weight chart line rendering: raw readings → centered 5-day moving average | product | active |
| [2026-06-14-1-weight-chart-line-smoothing-from-staircase](episodes/2026-06-14-1-weight-chart-line-smoothing-from-staircase.md) | 2026-06-14 | Weight chart line smoothing: from staircase monotone to centered moving average | product | superseded |
| [2026-06-17-1-landscape-chart-adds-window-stats-card](episodes/2026-06-17-1-landscape-chart-adds-window-stats-card.md) | 2026-06-17 | Landscape chart adds window stats card and pan/pinch navigation | product | active |
| [2026-06-17-1-landscape-focus-chart-contextual-stats-gesture](episodes/2026-06-17-1-landscape-focus-chart-contextual-stats-gesture.md) | 2026-06-17 | Landscape Focus Chart: Contextual Stats & Gesture Navigation | product | superseded |
| [2026-06-17-1-landscapefocuschart-window-stats-gesture-navigation](episodes/2026-06-17-1-landscapefocuschart-window-stats-gesture-navigation.md) | 2026-06-17 | LandscapeFocusChart Window Stats & Gesture Navigation | product | superseded |
| [2026-06-17-1-minichart-gains-swipeable-rate-of-change](episodes/2026-06-17-1-minichart-gains-swipeable-rate-of-change.md) | 2026-06-17 | Minichart gains swipeable rate-of-change page (1st derivative, not 2nd) | product | superseded |
| [2026-06-17-1-rate-chart-needs-signed-data-visual](episodes/2026-06-17-1-rate-chart-needs-signed-data-visual.md) | 2026-06-17 | Rate chart needs signed-data visual treatment, not weight-chart parity | product | superseded |
| [2026-06-17-1-rate-of-change-chart-added-as](episodes/2026-06-17-1-rate-of-change-chart-added-as.md) | 2026-06-17 | Rate-of-change chart added as swipeable second page to minichart | product | superseded |
| [2026-06-17-1-rate-of-change-chart-as-swipeable](episodes/2026-06-17-1-rate-of-change-chart-as-swipeable.md) | 2026-06-17 | Rate-of-change chart as swipeable second page on Today minichart | product | superseded |
| [2026-06-17-1-rate-of-change-chart-first-derivative](episodes/2026-06-17-1-rate-of-change-chart-first-derivative.md) | 2026-06-17 | Rate-of-change chart: first-derivative page with robust regression | product | superseded |
| [2026-06-17-1-rate-of-change-chart-page-added](episodes/2026-06-17-1-rate-of-change-chart-page-added.md) | 2026-06-17 | Rate-of-change chart page added to minichart | product | active |
| [2026-06-17-1-rate-of-change-chart-page-on](episodes/2026-06-17-1-rate-of-change-chart-page-on.md) | 2026-06-17 | Rate-of-change chart page on Today minichart | product | superseded |
| [2026-06-17-2-chart-area-fill-must-cover-full](episodes/2026-06-17-2-chart-area-fill-must-cover-full.md) | 2026-06-17 | Chart Area Fill Must Cover Full View Including Safe Area | root-cause | active |
| [2026-06-17-2-duplicate-daily-readings-timezone-day-boundary](episodes/2026-06-17-2-duplicate-daily-readings-timezone-day-boundary.md) | 2026-06-17 | Duplicate daily readings: timezone/day-boundary storage bug | root-cause | active |
| [2026-06-17-2-first-derivative-chosen-over-second-for](episodes/2026-06-17-2-first-derivative-chosen-over-second-for.md) | 2026-06-17 | First derivative chosen over second for rate-of-change chart | product | active |
| [2026-06-17-2-healthkit-self-re-import-duplicate-bug](episodes/2026-06-17-2-healthkit-self-re-import-duplicate-bug.md) | 2026-06-17 | HealthKit self-re-import duplicate bug diagnosed and fixed | root-cause | active |

