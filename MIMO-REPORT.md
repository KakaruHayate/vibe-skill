---
name: mimo-report
description: Show Mimo usage report — token/cost/failure stats. Usage: /mimo-report [--since N] [--project NAME] [--fails]
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /mimo-report

Run `~/tools/delegate-report --delegate mimo` (plus any flags extracted from the arguments) and display output verbatim.

| User says | Flag |
|-----------|------|
| "last 7 days", "7d" | `--since 7` |
| "last 30 days", "30d" | `--since 30` |
| "project foo" | `--project foo` |
| "only failures", "fails", "bugs" | `--fails` |
| "adapt", "adaptations", "by adaptation" | `--adapt` |
| "all delegates", "everything", "compare delegates" | `--all` (drops the default `--delegate mimo`) |
| "delegate foo", "only vibe" | `--delegate foo` (replaces the default) |
| (nothing) | `--delegate mimo` only — mimo runs only |

Defaults to mimo runs only. The run log is shared across delegate tools (mimo, vibe, opencode, gemini); `--all` shows every delegate, `--delegate NAME` scopes to a specific one.
