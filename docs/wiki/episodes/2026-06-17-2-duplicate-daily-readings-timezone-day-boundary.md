---
type: episode-card
date: 2026-06-17
session: 18aedfc3-5869-408c-a87a-9618ad497cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/18aedfc3-5869-408c-a87a-9618ad497cfa.jsonl
salience: root-cause
status: active
subjects:
  - reading-storage
  - day-boundary
  - deduplication
supersedes: []
related_claims: []
source_lines:
  - 938-1094
captured_at: 2026-06-17T09:03:36Z
---

# Episode: Duplicate daily readings: timezone/day-boundary storage bug

## Prior State

Readings were assumed to be one-per-day. The smoothing and rate computation used raw inCutReadings indexed by array position, so ~2 readings/day collapsed the effective smoothing window from ~14 days to ~2.5 days.

## Trigger

Data verification against the device store revealed 90 readings across only 50 calendar days — 40 days had two records ~1 hour apart (21:00Z and 22:00Z), the fingerprint of a DST/timezone bug in the dayStart boundary calculation when saving.

## Decision

Added per-calendar-day deduplication in the chart path (collapse to one point per day before smoothing and rate computation). The upstream storage bug is flagged but not fixed in this session.

## Consequences

- Chart smoothing and rate computation now operate on true daily resolution, producing a calmer, more accurate line
- The root cause (dayStart timezone handling producing two records per day) remains in the save path — new dupes will continue to accumulate
- Existing 80 duplicate records in the store need cleanup at the storage layer
- Other features consuming inCutReadings or allReadings may also be affected by duplicate-day data (projections, EMA, etc.)

## Open Tail

- Fix the day-boundary calculation in Reading.dayStart/save to prevent future duplicates
- Write a one-time migration to deduplicate existing stored readings
- Audit other consumers of allReadings for duplicate-sensitivity

## Evidence

- transcript lines 938-1094

