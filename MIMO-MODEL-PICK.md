---
name: mimo-model-pick
description: Override the Mimo model for all subsequent delegations. Usage: /mimo-model-pick <alias>
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /mimo-model-pick

Extract the alias from the user's arguments, look up the matching `-m provider/model`
string from the alias table below, then run:
`echo <-m value> > ~/.local/share/mimo-model.flag`

Confirm: "Model override set to <alias> (<-m value>) — all Mimo runs will use this model until /mimo-model-clear."

If no alias provided, list the available aliases below and ask the user to pick one.

**Available aliases:**

| Alias | -m value | Notes |
|-------|----------|-------|
| `auto` | `mimo/mimo-auto` | **Default** — free tier, no API key needed |
| `anthropic-sonnet` | `anthropic/claude-sonnet-4-6` | Requires ANTHROPIC_API_KEY configured via `mimo providers` |
| `anthropic-opus` | `anthropic/claude-opus-4-7` | Requires ANTHROPIC_API_KEY |
| `openai-gpt5` | `openai/gpt-5` | Requires OPENAI_API_KEY |
| `deepseek-v3` | `deepseek/deepseek-chat` | Requires DEEPSEEK_API_KEY |

To add a custom alias, edit this table and `tools/mimo-delegate.win` — the flag file
content is forwarded verbatim as `-m <value>` to `mimo run`, so any
`provider/model` string mimo accepts via `mimo providers` will work.
