# WeightTracker — Product Spec v1

**Status:** TestFlight v1.0 (build 2) shipped 2026-04-30.
**Audience:** Pablo (founder/PM). This is a product doc — what the thing is, how it behaves, what the user sees and feels, and what the underlying mechanics actually do.
**Source material:** five parallel research streams (competitor teardown, App Store reviews, Reddit/forum pain, sports-science validation, positioning) + the live codebase under `Sources/`.

---

## 0. The one sentence

> **WeightTracker is a weight tracker that thinks in cuts — it knows you started one, watches you run it, and tells you honestly, every morning, whether you're going to make it.**

Every product decision below either serves that sentence or gets cut.

---

## 1. The thesis

The category gets two things wrong:

1. **They don't know what a cut is.** Happy Scale, Libra, Apple Health, every smart-scale OEM app — they all model body weight as a single never-ending stream. Users running a deliberate cut (vacation, meet, photoshoot, wedding, "by my birthday") have to fake the structure with spreadsheets, app restarts, and parallel notes. The cut is the unit of work in the user's head; in every existing app it does not exist as a thing.
2. **They draw a single straight line into the future and call it a projection.** Daily scale weight has a standard deviation of ~1-1.5 kg from water, glycogen, sodium, training, and (for ~half the user base) menstrual cycle. A weekly fat-loss target of 0.5-1% body mass means signal-to-noise is roughly 0.5-1.0 at the weekly level. A single line implies precision the data does not support, lurches every weigh-in, and trains users to distrust the projection entirely. ("It said April 17, then April 11, then June 4.")

Both errors collapse into one underlying mistake: the category models *weight* when it should model *the cut*, and it shows *certainty* when it should show *variance*.

Our two beliefs, fused:

- **A cut is a first-class object.** It has a start date, a start weight, a target weight, a deadline, and an outcome. The product organizes around the active cut. History is a list of cuts. Today asks: are you on pace for the active cut?
- **A projection without uncertainty is a lie.** We show **best / typical / worst** trajectories to the deadline, and we tell you which **pacing** (required / typical / fast) you'd need to hit it. The "typical" line wiggles like real cuts wiggle, not like a fitted curve.

Cuts as the frame; variance-aware projections as the proof. They are not separable. A trend smoother with confidence intervals is just statistics. A cut with confidence intervals is a coach.

---

## 2. The wedge user (who the product is built around)

**Physique-focused lifters running a deliberate 8-16 week cut with a date in mind.** They already know how to eat. They will not log food. They weigh daily, own a smart scale, and live on Apple Watch. Their question every morning is **"am I on pace?"** — not "what's my ETA?"

Adjacent users we accept but don't optimize for in v1: women on planned cuts (cycle-aware mode is a v1.1 must-ship — see §10), grapplers/powerlifters making weight, GLP-1 users tracking a clinical trajectory.

Users we reject by design: general-wellness "journey" trackers, mindful-eating users, anyone without a deadline. If you don't have a deadline, you're not in a cut, and Apple Health is enough.

---

## 3. Anti-product (what we will not become)

We are not, and will refuse to become:

- **A food logger.** No barcode scanner, no macros, no recipe DB, ever.
- **A coach.** No anthropomorphized AI, no streaks, no "great job!" copy.
- **A social app.** No feed, no friends, no leaderboards. The scale is between the user and the math.
- **A general wellness tracker.** Not for pregnancy, not for chronic disease, not for "mindful eating," not for kids.
- **A medical product.** No body-fat coefficient gimmicks, no DEXA pretensions, no clinical claims.

Every quarter, re-read this list. Every refusal is a feature.

---

## 4. The product, in concrete terms

The app is four tabs (Today, Cuts, Trends, Settings), a Watch app, and a notification system. The active cut is the protagonist of every surface that isn't pure settings.

### 4.1 Today

The single screen the user opens every morning. Top to bottom:

1. **Numeric pad** for today's weight. Big tappable digits. Tap the unit symbol to toggle lbs↔kg.
2. **Optional details row** — waist, hips, free-text note. Collapsed by default.
3. **Save button** — single tap. The save fires confirmation haptic + a confirmation card that auto-dismisses.
4. **Active-cut minichart** — only renders when there is an active cut. ~100pt tall, charts:
   - The user's in-cut readings as dots.
   - The **best** projection ray (green).
   - The **typical** projection path with real residual wiggle (blue).
   - The **worst** projection ray (red).
   - The target weight as a dashed horizontal line.
   - The target end date as the right edge of the chart.
   - Tap → fullscreen chart with the same content larger.
5. **Confirmation card** — last save echoed back ("logged 187.4 lb at 7:42 am").
6. **Date navigator** — the title bar shows "Day N — Today" / "Day N — Yesterday" / a date picker. Swipe left/right or arrow-tap to log past days.

The Today screen is allowed to be empty *only* before there is an active cut. After a cut starts, it always has the minichart.

### 4.2 Cuts

The list of cuts, present and past.

- **Active cut card** (top): start weight → target weight, start date → deadline, days elapsed/remaining, an inline projection chart, and the projection summary ("on pace for typical").
- **Historical cuts list** (below): one card per past cut, with start/end weights, total loss, average rate (lb/wk), duration, and an inline weight chart of that cut's actual readings.
- **Start new cut sheet** — start date (defaults today), start weight (auto-populates from latest reading), target weight, deadline. One screen.
- **Edit cut sheet** — change target or deadline mid-cut. Editing the start data is locked once there are in-cut readings; the cut is what it is.
- **Tap any chart → fullscreen** with the same content larger and a unit toggle.

Historical cuts are **auto-detected** from the user's reading history (see §5.4). The user does not need to have used the app for past cuts to appear; they just need to have weight data (manual + HealthKit import).

### 4.3 Trends

The "what's actually been happening" view, separate from the active-cut narrative.

- **Right Now card** — your current weight, drift-estimated when the last reading is stale (uses the user's own historical drift rate, default 1.2 lb/month). Says explicitly when it's an estimate vs a real reading.
- **Drift bar chart** — periods of weight gain/loss as bars, magnitude colored by direction.
- **Era summaries** — auto-segmented life chapters (sustained gain, sustained loss, plateau) as a small table.
- **Gap detail sheet** — when the user has a long gap in their data, shows what the app inferred about it.

Trends is the "show me the truth" tab. It does not editorialize; it surfaces structure that's already in the data.

### 4.4 Watch

Today, the Watch is a logging utility:

- Crown-driven entry of weight.
- Saves to HealthKit + the App Group container.
- Syncs to the iPhone over the App Group when the phone is in range.

V1 ships only entry. The Watch as a *cut companion* (active-cut glance, on-pace headline, complication) is a v1.1 must-ship — see §10.

### 4.5 Settings

Quiet, complete, never the front door:

- **Display** — units (lb/kg, in/cm), theme (system/light/dark).
- **Data** — manual export (CSV), import (CSV), delete-range, wipe-all.
- **HealthKit** — read enabled, write enabled, source priority.
- **iCloud** — sync enabled (CloudKit container `iCloud.app.pfer.weighttracker`).
- **Reminders** — daily cut reminder time (defaults to 7:30 am), category toggles.
- **About** — version, build, links.

Settings is invisible when nothing's wrong. It exists for the moment the user has a question; until then, every screen above it has a sane default.

---

## 5. The mechanics (what's actually happening under the hood)

### 5.1 The reading

A `Reading` is a weight in kg, anchored to the **start of day** in the user's local calendar (so daily series math is unambiguous), with optional waist, hips, free-text note, source (`manual` / `healthKit` / `watch`), and device name. Day-collapsing happens at insertion: there is one logical reading per day per source. Multiple sources can coexist on the same day (e.g., a manual entry plus a smart-scale push); the projection engine treats them as one anchor point with a deterministic resolution rule.

### 5.2 The cut

`ActiveCut` is at most one at a time in v1, persisted as JSON in `AppPreferences` (`activeCutJSON`). Fields:

- `startDate` — when the cut began.
- `startWeightKg` — the locked-in starting weight (typically the user's recent average, not a single noisy reading).
- `targetWeightKg` — the user's goal weight.
- `targetEndDate` — the deadline.
- `dailyReminderSecondsAfterMidnight` — when to nudge.

`HistoricalCut` is the same shape minus the deadline plus a computed `avgRateKgPerWeek` and `durationDays`. Historical cuts feed the projection engine as the personal variance source.

### 5.3 The projection engine (the moat)

`Sources/Shared/Analysis/CutProjection.swift`. This is the most differentiated code in the product, and the spec for it lives in the file's doc comments. Pipeline:

1. **Anchor weight.** Trimmed mean of the user's last 7 in-cut readings: drop the single max and single min, mean the remaining 5. Kills daily noise without lying about the level. With <3 in-cut readings, falls back to the most recent reading. With zero in-cut readings, falls back to `startWeightKg`.
2. **Slopes** in %BW/wk, derived from the user's *own* historical cuts:
   - **Best** = mean of the 2 most-negative rates (with ≥5 historicals; otherwise the single most-negative).
   - **Typical** = the median rate.
   - **Worst** = mean of the 2 least-negative rates.
   - **Cold start** (no historicals): Helms 2014 natural-bodybuilding priors, **best -1.0 / typical -0.7 / worst -0.3 %BW/wk**.
3. **Best and worst paths** — straight rays from the anchor at those slopes.
4. **Typical (avg) path** — built by **circular block bootstrap** (block size 7) over the user's real residuals from the last two historical cuts (after trimming the first 14 days of each to exclude initial water-weight artifacts). The typical path therefore *wiggles like the user's actual cuts wiggled*, not like a fitted curve. With no residual pool available, the typical path is the deterministic median-rate ray.
5. **Floor cap** — projections are clamped above `max(targetWeightKg - 0.9, 0.85 * startWeightKg)`. Prevents pessimistic projections from drifting into unphysical territory.
6. **Target-reached state** — when anchor is within 0.5 kg of target, the projection switches off and the UI moves to a "you're there" mode.

The user never sees the words "circular block bootstrap." They see three lines that move plausibly. The bootstrap is the engine; the chart is the product.

### 5.4 Historical cut detection

`Sources/Shared/Analysis/HistoricalCutDetector.swift`. Runs over the user's full reading history clustered by `ClusterDetector` (continuous logging streaks). Inside each cluster, finds the **longest sub-range** that satisfies:

- Duration ≥10 days.
- Net loss > 0.
- Average rate ≥0.5 lb/wk.

Each qualifying range becomes a `HistoricalCut` with computed start/end dates and weights, total loss, average rate, and duration. The detector runs on every CSV/HealthKit import and on edit. The user does not start cuts manually for the algorithm to know they happened.

This is the cold-start unlock: a new user who imports six months of HealthKit data immediately gets one or two auto-detected cuts, which seed the projection engine with their own variance instead of generic priors.

### 5.5 Drift estimation

`Sources/Shared/Analysis/DriftEstimator.swift`. When the user's last reading is N days old, estimates current weight as `lastReadingLb + median(historical drift rate per month) * (N / 30)`. The median is taken over the user's gaps of ≥30 days. Default drift if the user has no gap history: **+1.2 lb/month** (the population-average passive weight gain in untracked adulthood). Surfaces in the Trends "Right Now" card with explicit "estimated" labeling.

### 5.6 Sleep correlation, gap analysis, cluster detection

Three derived analyses that surface in Trends and the chart overlays:

- **`SleepCorrelation`** reads HealthKit sleep data, computes weekly correlation with weight changes, surfaces as an overlay on the weight chart.
- **`GapAnalyzer`** detects multi-day gaps in logging, computes their drift, classifies them.
- **`ClusterDetector`** segments the user's entire history into continuous logging streaks (clusters) and gaps. Drives historical cut detection and era summaries.

These features earn their keep in Trends but should not encroach on Today.

---

## 6. The messaging contract (how the app talks to the user)

This is where most weight apps fail and we have to win. The user's emotional state during a cut runs from determined → frustrated → demoralized → relieved → triumphant, and the app's words during each phase determine whether they keep weighing.

**Rules:**

1. **Never cheerful during a stall.** No "great job!", no "you're doing amazing!", no streaks. During a plateau, say what's true: *"You're inside typical variance for day 23. Your last cut had a 9-day stall around this point that resolved with a 1.2 lb whoosh."* Data, not encouragement.
2. **Never pessimistic during noise.** A single bad weigh-in does not move the projection meaningfully because the anchor is a 5-of-7 trimmed mean. Don't let the UI imply otherwise.
3. **Always answer "am I on pace?" in one sentence.** The active-cut minichart's headline (v1.1 — see §10.1) is *"Day 23 of 84 — on pace for typical (need -0.6 lb/wk to hit deadline)."* That sentence is the most important pixel in the product.
4. **Honest about uncertainty.** Anywhere we show a single number ("you'll hit your target in X days"), we also show the range ("between Y and Z days"). The product would rather be vaguely right than precisely wrong.
5. **No dark patterns.** No "you'll lose your streak!", no nag screens, no upsell interstitials at emotional moments.
6. **No body-image editorializing.** We don't celebrate weight loss as morally good or weight gain as morally bad. The user has a goal; we report progress against it.

Notifications already wired in v1: `gapForming`, `gapDeepening`, `clusterBroken`, `cutDay` (daily reminder), `cutMilestone`, `cutStall`. Quiet hours, master switch, paused-until. Copy needs a v1.1 audit against the rules above — current strings are placeholders.

---

## 7. Onboarding and cold start (the activation path)

The onboarding flow in v1 (`Sources/iOS/Features/Onboarding/`):

1. **What it is** — one-screen explanation. Cuts, projections, honesty about variance.
2. **HealthKit** — request read + write permission. Explain why ("so we can see your past cuts and so other apps stay in sync").
3. **Import** — optional CSV import for users coming from another app.
4. **Reminders** — set daily cut reminder time. Optional.
5. **First cut** — start weight (auto-filled from latest reading), target weight, deadline. The user lands on Today with an active cut and a minichart already drawn.

**The cold-start problem.** The projection engine personalizes based on the user's own historical cuts. A brand-new user with no past data gets the Helms 2014 priors and a typical-path ray with no wiggle. That's mathematically correct but it means the wedge ("variance from your data") doesn't apply on day one.

**The fix (v1.1 must-ship — see §10.4):** Onboarding pulls the user's last 6-12 months of body mass from HealthKit silently in step 2, runs cluster + historical cut detection, and surfaces "we found your last cut — June 5 to August 12, you lost 11 pounds at 0.9 lb/week. We'll use it to make your projections personal." That sentence is the activation hinge. If we land it, the new user lives in the personalized variance world from day one.

Until cold-start is solved, the empty-band state must be honest: "Typical band is based on average natural-cut rates. It will tighten with your own data after this cut."

---

## 8. What v1 already does best

- **Variance-aware projection.** Nothing in the consumer category ships best/typical/worst grounded in the user's own residuals. This is real and shippable today.
- **Cuts as durable, auto-detected first-class objects.** AggressiveCut is the closest philosophical neighbor in the market and even they treat a "cut" as a nutrition plan, not a tracker primitive.
- **Watch entry that actually works offline.** Solves the "phone must be open" complaint that dings every Watch weight app. App Group + HealthKit gives independent entry that reconciles when the phone is in range.
- **Drift estimation.** When the user disappears for a month and comes back, we don't pretend the last reading is current. Few apps do this; none do it gracefully.

---

## 9. What v1 doesn't yet do (product gaps the wedge user will notice)

1. **The "on pace" headline.** We have the chart but not the sentence. The chart is proof; the sentence is the answer. This is the single highest-leverage UI change in the product.
2. **Post-cut debrief.** When a cut ends — target hit, deadline passed, or user-ended — we have nothing. No celebration, no forensic comparison of actual vs projected, no shareable artifact. This is the loop and the proof of the product.
3. **Cycle-aware projections.** Roughly half the addressable user base has a 1-5 lb cyclic water-retention overlay tied to menstrual phase. Almost no app models this. A cycle-phase covariate would *attribute apparent stalls to phase rather than diet failure* and tighten the typical band on non-luteal weeks. The science is unambiguous; the UX is opt-in.
4. **Forecast-to-date.** "What will I weigh on `<picked date>`?" is the single most-loved feature in Happy Scale and Libra reviews. We have the math; we don't surface the question.
5. **Smart stall messaging.** We have the `cutStall` notification but the in-app copy during a plateau is not yet data-grounded. See §6.1.
6. **Watch as a cut companion.** Currently entry-only. No active-cut glance, no on-pace summary, no projection complication. The wedge user lives on Apple Watch.
7. **Onboarding from past data.** The cold-start fix in §7 is not yet built. New users today get the Helms prior for 8-16 weeks before the wedge becomes real.
8. **Multiple cuts in a year.** The `ActiveCut` slot is single. Lifters typically run 1-2 cuts per year with maintenance and small bulk phases between. No multi-cut planning, no future-cut scheduling.
9. **Editing readings in bulk.** Per-reading edits exist; bulk corrections (e.g., "shift everything 0.3 lb because I recalibrated my scale") don't.
10. **"Why did the projection move?" explainability.** When the typical path shifts week-over-week, the user has no way to ask why. A small disclosure ("typical rate updated because your last 7-day trimmed mean changed by 0.4 lb") would buy a lot of trust.

---

## 10. v1.1 product roadmap

In execution order. Each item must serve the one sentence in §0.

### 10.1 The "on pace" headline on Today

The active-cut minichart gets a one-sentence headline above it:

> **Day 23 of 84 — on pace for typical**
> Need -0.6 lb/wk to hit your deadline.

The phrase changes based on where the anchor sits relative to the three projection rays:
- Anchor below the "best" ray → *"ahead of best — you're crushing this cut."*
- Between best and typical → *"on pace for best."*
- Between typical and worst → *"on pace for typical."*
- Below worst → *"behind your typical — need X lb/wk to hit your deadline."*
- Inside ±the bootstrap noise band of the typical path → *"inside typical variance — keep going."*

This sentence is the answer to the morning question. The chart is the proof.

### 10.2 Post-cut debrief

When a cut ends (target reached, deadline passed, or user-ended), generate a one-screen forensic:

- Final weight vs target (delta, %BW).
- Actual trajectory overlaid on the original best/typical/worst projection bands.
- Adherence: days logged out of total days.
- Drift summary: biggest stall (duration, location), biggest whoosh (magnitude, location).
- Average rate vs your historical typical.
- The cut card in Cuts gets the debrief as its detail view forever.
- A shareable PNG (one button): clean rendering of the actual-vs-projected chart with the user's anonymized stats.

This is the closing chapter of the cut narrative. It's also the strongest organic share artifact.

### 10.3 Smart stall messaging

The `cutStall` notification and the in-app "stall acknowledgment" both speak data, not encouragement. Pulled from the user's history:

- *"You've been within 0.4 lb of your trimmed mean for 8 days. Your last cut had a 9-day stall around this point that resolved with a 1.2 lb whoosh."*
- *"This is day 23. Your weight is 0.6 lb higher than yesterday — that's inside the daily noise band of your last cut (±1.4 lb)."*

Built on existing notification scaffolding + historical cut data. No new infra.

### 10.4 Onboarding from Apple Health (cold-start fix)

In the HealthKit step of onboarding, silently pull the user's last 12 months of body mass, run cluster + historical cut detection, and surface the result:

> **We found your last cut.**
> June 5 → August 12, 2025. You lost 11.2 lb at 0.94 lb/week.
> We'll use it to make your projections personal from day one.
> [Use this cut] [Ignore]

If multiple cuts are found, surface them as a list. If none are found, gracefully fall back to the prior-based projection with the honest copy from §7.

### 10.5 Cycle-aware projections (opt-in)

In Settings → Display (or a new "Body" section): toggle "I track menstrual cycle." If on, read cycle data from HealthKit (with explicit additional permission) and add a cycle-phase covariate to the projection's residual model:

- Luteal weeks → wider typical band, attribution language ("this stall is consistent with luteal-phase water retention").
- Non-luteal weeks → tighter band, full-confidence pacing language.

The user can also just see "you're in luteal phase, day 4 of 7" as a small label on the active-cut chart — that label alone resolves a lot of "why did I gain 3 lb overnight?" anxiety without changing a single number.

### 10.6 Watch active-cut glance + complication

- **Glance** in the Watch app: "Day 23 of 84 — on pace for typical." Same headline as Today, on the wrist.
- **Complication** (modular small + corner + circular): the day count and a single-letter pace status (B/T/W). Tap → opens the Watch app to the active-cut view.

### 10.7 Forecast-to-date

A small "what will I weigh by `<date>`?" picker in the active-cut card. Returns a range (best–worst) plus the typical, not a single number. Powered by the existing projection engine with a different end date.

### 10.8 "Why did this move?" disclosure

Tap on the projection chart's headline (v1.1 §10.1) → a small sheet explaining the inputs:

- Anchor: trimmed mean of last 7 readings = X.X lb.
- Typical rate: median of your last 3 cuts' rates = Y.Y lb/wk.
- Best/worst rates: drawn from your fastest/slowest historical cuts.
- Days remaining: N.

Trust comes from being able to see the math when you want to.

---

## 11. Things deferred (explicitly NOT in v1.1)

- Food logging in any form.
- AI coach / chat / nudges.
- Social sharing beyond the debrief PNG.
- GLP-1 mode.
- Multi-user (family) on Watch.
- Body-fat estimation from waist/hips ratios.
- Photo progress logs.
- Apple Watch independent cellular install.
- Widgets (deferred to v1.2 — they're nice but the watch face is the home).

---

## 12. Open product questions (the real fork-in-the-road decisions)

1. **Single-cut vs multi-cut data model.** v1 stores the active cut as JSON in preferences. Past cuts are auto-detected and stateless. If we want the user to *plan* their next cut while still in the current one, the model needs to support `[FutureCut]` alongside `ActiveCut`. Decide before any cycle-aware work, because that's where multi-cut state pressure builds.
2. **How does the projection earn trust on day one when there's no history?** §7 proposes the cold-start fix, but there's still a fraction of users who land with zero HealthKit data. For them, what's the day-one experience that doesn't feel generic? Possibilities: show a public "typical lifter cut" composite as the prior, let the user pick "I lift / I don't" for slightly different priors, or just be radically honest in copy.
3. **What is a "stall" formally?** v1 has `cutStall` notification logic but no published threshold in this doc. Suggest: ≥7 days where the trimmed mean has moved <0.3% BW. Decide and write it down.
4. **Should the typical path's bootstrap wiggle be visible by default, or only on tap?** The wiggle is the most novel visual element in the product and also the most easily misread ("why is the future zigzagging?"). Test both: wiggled-by-default vs smooth-typical-with-wiggle-band-on-tap.
5. **What happens at the moment of target-reached?** Currently the projection switches off and the UI says "you're there." But the user is mid-cut emotionally; the deadline hasn't arrived. Do we offer a "hold and stabilize" mode? A "extend the cut" prompt? An immediate debrief? Decide with the post-cut debrief design.
6. **How does cycle-aware mode interact with the wedge user?** The wedge user is mostly male and won't toggle it on. The mode shouldn't dilute the male-default experience or muddy the marketing language. Make it invisible until enabled.
7. **CSV import dedup rules.** A user importing from Happy Scale or Libra will have many same-day duplicates and conflicting source data. v1's behavior is "last writer wins per day per source." Confirm this is right or design the merge UI.

---

## 13. Product principles (the non-negotiables)

A short list to hand to any future contributor:

1. **The cut is the protagonist.** Every screen's design starts from "where is this in the user's active cut?"
2. **Show variance, not certainty.** Any projected number gets a range. Any single line gets a band.
3. **Trim the noise; don't smooth the truth.** Anchor on trimmed means, not regressions over short windows. Show real wiggle in projections.
4. **Speak data during emotional moments.** Stalls and slow weeks earn explanations, not encouragement.
5. **The Watch is not a peripheral.** It's the wrist-side of the cut. Logging and the on-pace glance should both feel native there.
6. **Apple Health is the spine.** Two-way sync, never the sole source of truth, never a black box to the user.
7. **Settings are quiet.** Defaults that work; complexity hidden until needed.
8. **Refuse what we are not.** Re-read §3 every quarter.
