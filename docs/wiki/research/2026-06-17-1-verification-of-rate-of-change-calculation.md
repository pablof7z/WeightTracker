---
type: research-record
date: 2026-06-17
session: 18aedfc3-5869-408c-a87a-9618ad497cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/18aedfc3-5869-408c-a87a-9618ad497cfa.jsonl
source_lines: 985-1009
agent_attribution: main
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Verification of rate-of-change calculation correctness and discovery of duplicate-readings data bug, with cross-validation against ground truth"
captured_at: 2026-06-17T09:30:11Z
---

Verification of rate-of-change calculation correctness and discovery of duplicate-readings data bug, with cross-validation against ground truth

---

Assistant: Verified against your real data — here's the verdict:

## ✅ The calculation is sound

The headline **−1.9 lb/wk is correct.** I recomputed it three independent ways from your raw readings and cross-checked against ground truth:

| Method | Result |
|---|---|
| App's rate (last point) | **−1.93 lb/wk** |
| Raw 30-day regression | −1.88 lb/wk |
| Whole-cut regression | −1.98 lb/wk |
| **Ground truth** (176.2 → 162.2 lb = −14.0 lb over 50 days) | **−1.96 lb/wk** |

They all agree. The math isn't off.

## 🐞 But I found a real data bug — that's what looks "weird"

**40 of your 50 cut-days have a duplicate reading stored ~1 hour apart**, e.g.:
```
2026-06-05T21:00:00Z  74.707 kg
2026-06-05T22:00:00Z  74.707 kg   ← same value, +1h
```
That 21:00Z / 22:00Z split is the fingerprint of a **timezone/DST bug** in how day-boundaries are computed when saving — local "midnight" is landing on two different UTC instants, so you get two records per day. There are **90 readings across only 50 calendar days.**

This doesn't bias the *rate* (the dupes are identical, so the slope is unaffected — which is why the headline is still correct). But it **wrecks the smoothing**: the 5-day average is indexed by *reading*, not *day*, so with ~2 readings/day it actually only spans ~2.5 real days → the line is far noisier than it should be. Combine that with genuine water swings (Jun 15 jumped +2.4 lb then −2.8 lb the next day) and you get the jagged shape.
