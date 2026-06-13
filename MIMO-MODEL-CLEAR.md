---
name: mimo-model-clear
description: Clear the Mimo model override and revert to the mimo default (mimo-auto on free tier).
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /mimo-model-clear

Run: `rm -f ~/.local/share/mimo-model.flag`

Confirm: "Model override cleared — Mimo will use mimo-auto (free tier) unless mimo's own provider config overrides it."
