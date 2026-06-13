---
name: mimooff
description: Disable Mimo auto-delegate mode — coding tasks are handled by Claude directly unless /mimo is explicitly invoked.
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /mimooff

Run: `rm -f ~/.local/share/mimo-auto.flag`

Then confirm: "Auto-mimo OFF — Claude will handle coding tasks directly."
