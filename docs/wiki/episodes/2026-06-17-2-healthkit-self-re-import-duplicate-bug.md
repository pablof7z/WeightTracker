---
type: episode-card
date: 2026-06-17
session: 18aedfc3-5869-408c-a87a-9618ad497cfa
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/18aedfc3-5869-408c-a87a-9618ad497cfa.jsonl
salience: root-cause
status: active
subjects:
  - healthkit-sync
  - reading-deduplication
  - reading-daystart
supersedes: []
related_claims: []
source_lines:
  - 1097-1620
captured_at: 2026-06-17T09:30:41Z
---

# Episode: HealthKit self-re-import duplicate bug diagnosed and fixed

## Prior State

HealthKit observer re-imported the app's own writes as new readings; day matching used exact-timestamp equality on Reading.dayStart (which was sensitive to DST); in-app delete/edit left orphaned samples in Apple Health.

## Trigger

User noticed weird data on the new rate chart; investigation showed 40 of 50 cut-days had duplicate readings (one manual, one healthKit with same weight, 1h apart). User hypothesized the app was writing to Health and re-importing its own write — confirmed by source field showing 'healthKit' + device 'WeightTracker' on the duplicate.

## Decision

Four-part fix: (1) ingest() now skips HealthKit samples attributed to our own bundle when a local reading already exists for that day; (2) reading(on:) uses a ±12h window instead of exact Date equality for DST-robust matching; (3) in-app delete and edit paths now call HKHealthStore.deleteObject for the corresponding Health sample; (4) one-time migration (ReadingDeduper.dedupe) collapsed the 40 existing duplicates, preferring manual over healthKit source.

## Consequences

- 530 → 490 readings after cleanup; in-cut readings 90 → 50, zero duplicate days remaining.
- Apple Health remains a valid restore source after reinstall (self-authored samples are only skipped when a local copy exists, not blanket-filtered).
- The accidental Jun 17 entry (73.94) deleted in-app but left in Health before this fix is still an orphan there — requires manual cleanup or one-shot deletion.
- Reading.dayStart timezone fragility documented in project memory as a recurring hazard.

## Open Tail

- Orphaned Health sample from Jun 17 (the accidental weight the user deleted in-app but which persists in Health) still needs cleanup.

## Evidence

- transcript lines 1097-1620

