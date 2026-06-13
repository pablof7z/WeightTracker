---
title: Secrets and Repo Hygiene
slug: secrets-and-repo-hygiene
topic: secrets-management
summary: All credentials (OpenRouter, ElevenLabs, Nostr) are stored in the Keychain at runtime rather than hardcoded in the repo
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

All credentials (OpenRouter, ElevenLabs, Nostr) are stored in the Keychain at runtime rather than hardcoded in the repo. The MEMORY/WORK/ directory must be excluded from git tracking and added to .gitignore before the repo is made public. The support email pfer@me.com is intentionally hardcoded in AboutSection.swift. Old git commits still contain PRD files in history and would need history rewriting (e.g. git filter-repo) to fully scrub before going public. <!-- [^85cf8-1] -->
