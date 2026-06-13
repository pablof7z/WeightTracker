---
title: Secrets and Repo Hygiene
slug: secrets-and-repo-hygiene
topic: secrets-management
summary: The repository is publicly accessible
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-13
updated: 2026-06-13
verified: 2026-06-13
compiled-from: conversation
sources:
  - session:85cf8353-385b-46d9-81aa-55592b40c0b9
---

# Secrets and Repo Hygiene

## Repository Hygiene & Secrets

The repository is publicly accessible. The MEMORY/ directory is excluded from git tracking via .gitignore. Git history is scrubbed of the MEMORY/WORK/ directory contents. All credentials (OpenRouter, ElevenLabs, Nostr) are stored in the Keychain at runtime, not hardcoded. The support email pfer@me.com is intentionally hardcoded in AboutSection.swift.

<!-- citations: [^85cf8-1] [^85cf8-2] -->
