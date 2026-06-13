---
title: Coach Conversation Thread
slug: coach-conversation-thread
topic: coach-interaction
summary: All coach interactionsâcheck-ins, proposals, observations, and coach-initiated messagesâare unified into a single persistent thread, replacing the previous
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
  - session:eec950200b72c009d85997c6660fd6285abbd97a2acfd2ed54fc27a8bc42ecdd
  - session:2a2f615736234996267fd99dc37f49ddf3efcd23e2a4839c507ef8041c1b57ba
---

# Coach Conversation Thread

## Unified Coach Thread

All coach interactions—check-ins, proposals, observations, and coach-initiated messages—are unified into a single persistent thread, replacing the previous parallel history + card-stack system. Proposals appear as message types within the coach thread rather than as cold algorithmic cards. The CoachBriefingView is rewritten as a unified thread view replacing the previous card-stack interface, and the CoachConversationController and CoachConversationSheet are rebuilt as text-based (no TTS) with note persistence. The coach replies via text, not TTS, for the most part. <!-- [^cd8bc-2] -->


Both CoachRunTrigger and CoachAgentRunTrigger enums include a .conversation case, mapped between each other by raw value. <!-- [^eec95-4] -->
## Voice Input Handling

Tapping the microphone button on the Today screen opens a voice recording sheet instead of the previous chat UI. The voice recording sheet auto-starts recording on appear, placing the user directly into microphone mode. A short tap recording uses a fire-and-forget pattern, auto-sending the voice message after recording finishes with no manual send required. A long-press on the microphone keeps the recording sheet open to support multi-turn conversations. After the agent replies, a microphone button appears to start the next turn in the conversation. Voice notes are persisted and the agent session's runTurn() is called directly without duplicating persistence through CoachConversationController. The sheet displays a thread of notes and proposals filtered to the current session. The conversation thread maintains continuity so each message is part of the same conversation rather than independent from previous ones. The agent responds to voice messages with text or inline widgets (e.g., rendering plan adjustments as inlined widgets rather than plain text).

<!-- citations: [^cd8bc-3] [^2a2f6-1] -->
## Today View Pinned Note

The Today view displays a pinned note from the coach that the user can see and dismiss. The note appears only when the coach explicitly sends one (e.g., 'Today focus on xxx'), not automatically for any reason. The coach agent has a `pin_today_note` tool that allows it to explicitly pin a note to the Today view, and the pinned note includes a dismiss button allowing the user to dismiss it. <!-- [^cd8bc-4] -->
