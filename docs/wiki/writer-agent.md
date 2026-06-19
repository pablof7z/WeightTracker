---
title: Writer Agent
slug: writer-agent
topic: writer-agent
summary: The writer agent is defined in ~/.tenex/edge/agents-definition/writer.json
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-17
updated: 2026-06-17
verified: 2026-06-17
compiled-from: conversation
sources:
  - session:7076d8bd-012b-4071-823c-733c3b2fb2e3
  - session:00f6109b-0c81-40e9-a6c3-1c98c927c324
---

# Writer Agent

## Definition

The writer agent is defined in ~/.tenex/edge/agents-definition/writer.json. To launch it via Claude Code, the tenex-edge launcher reads the JSON file and passes its system_prompt using --system-prompt (extracted via jq), since the claude CLI's --agent flag accepts an agent name/alias rather than a file path. The --agents flag accepts an inline JSON string, not a file path.

<!-- citations: [^7076d-1] [^00f61-3] [^00f61-5] -->
## Purpose

The writer agent writes tweets and seeks engagement on behalf of the user. It writes in a builder voice with no marketing fluff, showing the thing. <!-- [^7076d-2] -->

## Platforms

The writer agent posts to Twitter, Hacker News (Show HN / Ask HN / comments), Reddit (r/swift, r/iOSProgramming, etc.), and Indie Hackers. <!-- [^7076d-3] -->

## Drafting & Approval

The writer agent drafts 2–3 tweet variants before publishing and waits for user approval. It checks prior posts before drafting to avoid repeating angles. <!-- [^7076d-4] -->

## Record-Keeping

The writer agent keeps a record of things it wrote and people it engaged. Post records are stored in ~/.tenex/edge/agents-definition/writer-state/posts.jsonl as a JSONL log of every drafted or published tweet/post/comment. People records are stored in ~/.tenex/edge/agents-definition/writer-state/people.jsonl as a JSONL log of everyone engaged with, including relationship warmth and context. <!-- [^7076d-5] -->
