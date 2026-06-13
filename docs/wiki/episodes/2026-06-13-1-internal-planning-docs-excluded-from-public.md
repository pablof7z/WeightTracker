---
type: episode-card
date: 2026-06-13
session: 85cf8353-385b-46d9-81aa-55592b40c0b9
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-cut-tracker/85cf8353-385b-46d9-81aa-55592b40c0b9.jsonl
salience: architecture
status: active
subjects:
  - repo-visibility
  - memory-work-gitignore
supersedes: []
related_claims: []
source_lines:
  - 1-137
captured_at: 2026-06-13T21:28:31Z
---

# Episode: Internal planning docs excluded from public repo

## Prior State

MEMORY/WORK directory (containing internal PRDs with local absolute paths, team name, and development notes) was tracked in git and committed. No .gitignore existed in the repo.

## Trigger

User asked to evaluate the repo for going public; scan revealed MEMORY/WORK contained internal planning artifacts with personal paths and org details that should not be publicly visible.

## Decision

Remove MEMORY/WORK from git tracking and add a .gitignore that excludes it (plus build artifacts). Keep files locally but untracked.

## Consequences

- MEMORY/WORK directory contents are no longer in the working tree of the repo
- Old git commits still contain the PRD files — full scrubbing would require history rewriting (e.g. git filter-repo)
- No .gitignore existed before; now build/ and MEMORY/ are excluded

## Open Tail

- Git history still contains all removed MEMORY/WORK PRD files — user was offered git filter-repo to fully scrub them before going public

## Evidence

- transcript lines 1-137

