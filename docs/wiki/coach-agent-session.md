---
title: Coach Agent Session
slug: coach-agent-session
topic: coach-interaction
summary: The `CoachAgentSession.finishSucceeded()` auto-save mode is changed to `auditOnly`.
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-11
updated: 2026-05-11
verified: 2026-05-11
compiled-from: conversation
sources:
  - session:cd8bc54a9103307be1d24a59d8a90447a7c170ed9a7a81869aa6bdf148f4e10b
  - session:3059739a53f0b6574db54c73cc9b1ffca838e9ed56cf54ad9be63d9dc3624f35
  - session:eec950200b72c009d85997c6660fd6285abbd97a2acfd2ed54fc27a8bc42ecdd
---

# Coach Agent Session

## CoachAgentSession Configuration

The `CoachAgentSession.finishSucceeded()` auto-save mode is changed to `auditOnly`. <!-- [^cd8bc-1] -->


The `CoachAgentSession.finishSucceeded()` auto-save mode is changed to `auditOnly`. The `CoachAgentSession.runTurn()` method (used by Coach tab conversations) must call `auditStore.beginRun()` before the LLM loop and `auditStore.finishRun()` on every exit path (network error → .failed, JSON decode error → .failed, clean response → .succeeded with finalResponseJSON, turn cap → .succeeded with note). All tool dispatches in `runTurn()` must use the real runID from the audit store instead of generating a random UUID(). <!-- [^eec95-2] -->
## Date & Timestamp Encoding

Day-keyed dates in coach snapshot encoders are serialized with the user's local timezone offset (e.g. +02:00) so that 'yesterday' maps to yesterday in the agent's context. Real timestamps (generatedAt, lastUpdated, createdAt) remain correctly encoded when using the local-timezone-offset ISO8601 strategy. <!-- [^30597-4] -->

## Migration & Backward Compatibility

Historical contextSnapshotJSON rows already persisted in the audit store retain the old UTC encoding; only new runs produce the correct local-offset encoding. <!-- [^30597-5] -->

## Future Follow-ups

Adding the user's current local date to the system prompt ('Today is YYYY-MM-DD in the user's local timezone.') is a future follow-up defense-in-depth measure, out of scope for the current data fix. <!-- [^30597-6] -->

## Audit Requirement

Every LLM call must be fully auditable, capturing the messages array and related context in the Audit store. <!-- [^eec95-1] -->

## UI Audit Views

The `.conversation` trigger case must be handled in the exhaustive switches in `AgentAuditSettingsView.swift` and `CoachAuditSheet.swift`. <!-- [^eec95-3] -->
