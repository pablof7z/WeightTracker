---
title: Claude Skills System
slug: claude-skills-system
topic: skills
summary: Personal (user-level) skills are stored as directories under `~/.claude/skills/<skill-name>/` and are available across all projects
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-04
updated: 2026-05-04
verified: 2026-05-04
compiled-from: conversation
sources:
  - session:a37a4281a6d07868ca1ff692f79b73b4c064f6100015df532c7c585924889b8e
---

# Claude Skills System

## Skill Storage & Scoping

Personal (user-level) skills are stored as directories under `~/.claude/skills/<skill-name>/` and are available across all projects. Project-scoped skills are stored as directories under `.claude/skills/<skill-name>/` in the project root and are shared via the repo. Plugin skills are installed via `/plugin` from a marketplace and are managed automatically. <!-- [^a37a4-1] -->

## Skill Directory Structure

Each skill directory contains a `SKILL.md` file with YAML frontmatter requiring at minimum `name` and `description` fields, followed by a Markdown body containing the skill instructions. The `description` field in a skill's frontmatter determines when the skill is invoked, so it must clearly state what the skill does and when to use it. A skill directory can optionally contain additional helper scripts or files that the skill instructions can reference. <!-- [^a37a4-2] -->

## Skill Invocation

Skills can be explicitly invoked by typing `/<skill-name>` or automatically invoked via the Skill tool when a request matches the skill's description. <!-- [^a37a4-3] -->

## Skill Discovery & Session Constraints

Skills are auto-discovered on startup (next session), not mid-session. The current environment does not have a `skills_set` MCP tool; new skills cannot be enabled mid-session via a tool call and must instead be scaffolded on disk to be available in the next session. <!-- [^a37a4-4] -->

## Currently Available Skills

The currently available skills in this environment are: update-config, keybindings-help, simplify, fewer-permission-prompts, loop, schedule, claude-api, init, review, security-review. <!-- [^a37a4-5] -->
