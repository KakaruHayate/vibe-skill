---
name: mimostatus
description: Show Mimo auto-delegate mode status (ON/OFF) and active model override.
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /mimostatus

Run both checks and print two lines:

```
Auto-mimo: ON | OFF
Model: <-m value>  (override)  OR  Model: (mimo default — mimo-auto on free tier)
```

- Auto-mimo: `test -f ~/.local/share/mimo-auto.flag && echo ON || echo OFF`
- Model override: `cat ~/.local/share/mimo-model.flag 2>/dev/null || echo "(mimo default)"`
