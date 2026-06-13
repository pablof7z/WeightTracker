---
title: What's New Feature
slug: whats-new-feature
topic: ui-components
summary: The What's New feature informs users about recent changes
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-15
updated: 2026-05-15
verified: 2026-05-15
compiled-from: conversation
sources:
  - session:23551144fdc50173d406f169097fdf6df6f198933853094626286743eb684968
---

# What's New Feature

## Overview

The What's New feature informs users about recent changes. The podcast app at `../podcast` serves as the reference implementation. <!-- [^23551-1] -->

## Presentation

The What's New feature presents as a half-sheet on cold launch. It uses `.sheet(item:)` instead of `.sheet(isPresented:)` to avoid render-race bugs. <!-- [^23551-2] -->

## Data Model and Storage

The What's New feature uses a bundled JSON changelog with timestamp-based diffing. It seeds on first install to avoid dumping the full changelog on new users. It performs a dual-path marker write to correctly handle swipe-dismiss scenarios. <!-- [^23551-3] -->

## Error Handling

The What's New feature uses fail-closed loading so the app never crashes on launch. <!-- [^23551-4] -->

## Testing

The What's New feature has 10 unit tests. <!-- [^23551-5] -->
