---
name: mimo
description: >
  Delegate a coding task to MiMoCode (free tier, mimo-auto) and supervise the result via git diff.
  Trigger: /mimo <instruction>. Claude orchestrates, Mimo codes.
  Also handles /mimo-report [--since N] [--project NAME] [--fails] — token/cost/failure report.
license: MIT
user-invocable: true
allowed-tools:
  - bash
  - read_file
  - grep
---

# Mimo Orchestrator

## /mimoon | /mimooff | /mimostatus

Toggle auto-delegate mode — Mimo automatically handles coding tasks without requiring `/mimo` each time.

| Command | Action |
|---------|--------|
| `/mimoon` | `touch ~/.local/share/mimo-auto.flag → "Auto-mimo ON" |
| `/mimooff` | `rm -f ~/.local/share/mimo-auto.flag` → confirm "Auto-mimo OFF" |
| `/mimostatus` | report auto-mode (ON/OFF) **and** active model override |

For `/mimostatus`, run both checks and print two lines:
```
Auto-mimo: ON | OFF
Model: <alias>  (override)  OR  Model: (mimo default — mimo-auto on free tier)
```

### Auto-mode pre-filter (when flag is set)

When `mimo-auto.flag` exists, apply this gate **before** loading the full skill:

| Task signal | Action |
|---|---|
| 1 file, ≤10 lines, exact location already known | Edit directly — do NOT invoke the skill |
| Logic non-trivial, location unclear, multiple files, HTML/JS content, or >1 change | Invoke `/mimo` as normal |

---

## /mimo-report

If the user invokes `/mimo-report`, run `~/tools/delegate-report` with any flags
extracted from the arguments, display output verbatim, and stop.

| User says | Flag |
|-----------|------|
| "last 7 days", "7d" | `--since 7` |
| "last 30 days", "30d" | `--since 30` |
| "project foo" | `--project foo` |
| "only failures", "fails", "bugs" | `--fails` |
| "adapt", "adaptations", "by adaptation" | `--adapt` |
| "all delegates", "everything", "compare delegates" | `--all` |
| "delegate foo", "only opencode" | `--delegate foo` |
| (nothing) | (no flags — mimo runs only) |

The report defaults to **mimo runs only**. The log is shared across delegate
tools (mimo, vibe, opencode, gemini); use `--all` for the cross-delegate comparison
or `--delegate NAME` to scope to a different one.

---

## /mimo-model-pick | /mimo-model-clear

Override the Mimo model for all subsequent delegations.

| Command | Action |
|---------|--------|
| `/mimo-model-pick <alias>` | `echo <-m value> > ~/.local/share/mimo-model.flag` → confirm |
| `/mimo-model-clear` | `rm -f ~/.local/share/mimo-model.flag` → confirm "back to config default" |

**Available aliases** (writes the `-m provider/model` string to the flag file):

| Alias | -m value | Notes |
|-------|----------|-------|
| `auto` | `mimo/mimo-auto` | **Default** — free tier, no API key needed |
| `anthropic-sonnet` | `anthropic/claude-sonnet-4-6` | Requires ANTHROPIC_API_KEY configured via `mimo providers` |
| `anthropic-opus` | `anthropic/claude-opus-4-7` | Requires ANTHROPIC_API_KEY |
| `openai-gpt5` | `openai/gpt-5` | Requires OPENAI_API_KEY |
| `deepseek-v3` | `deepseek/deepseek-chat` | Requires DEEPSEEK_API_KEY |

The mimo default (no flag set) is `mimo-auto` from the free tier — runs at $0.

Run the bash command, print one confirmation line showing the active model, and stop.

---

When the user invokes `/mimo <instruction>`, Claude delegates the implementation
to MiMoCode via its `mimo run --format json --dangerously-skip-permissions` mode,
supervises in real time, and reports.

---

## Known Limits

Hard constraints — not config options. Full details in `SKILL-reference.md`.

- **UTF-8 / special chars** → an `edit` whose `oldString` doesn't match byte-for-byte
  returns an error status. Grep the literal anchor locally before delegating; pass
  it via `--require "anchor"` to abort before launch if it's gone.
- **Code duplication** → Mimo may re-insert a block already written. Grep for
  duplicate definitions after every run.
- **HTML in prompt** → tags like `<div>` are shell redirects (exit 127) when the
  prompt is interpolated naively. The script writes the prompt to a temp file —
  safe — but if you pipe HTML through a shell wrapper yourself, write it to a
  file first and reference the path in the prompt.
- **Source code in bash heredoc** → quotes/backslashes mangle. Use `edit`
  directly; never a helper script that replaces code.
- **Open-ended prompts on large files** → on files >300 LOC, prompts that
  describe a bug ("fix this method, here's the buggy code…") often cause the
  model to spend its output budget writing prose **before any tool call**.
  Symptom: `Tool calls: 0` or 1, output tokens 1000+, timeout, empty diff.
  **Fix**: rephrase as a closed-form OLD/NEW prompt (Step 3) when the change is
  precisely known. Evidence carried over from vibe-skill: a 600-line C# file
  flipped from `0 tool calls / 188s timeout` (open-ended) to `2 tool calls /
  35s / exit 0` (closed-form). Equivalent measurements on mimo-auto TBD on
  first real workload.
- **No --max-turns** → unlike vibe, mimo manages its own turn budget. The 3rd
  positional arg to mimo-delegate is recorded in the log only; the only real
  safety is wall-clock timeout. Bump `timeout-secs` (5th arg) for large refactors.
- **Free tier (mimo-auto)** → cost is $0 per the `step_finish.cost` field, but
  free tier may rate-limit per-fingerprint. If runs start returning empty
  output / quick errors, check `mimo providers` to see if the free quota is
  exhausted, and fall back to `/mimo-model-pick anthropic-sonnet` (if you have
  a key) or wait.
- **`MIMO_WIN_PREAMBLE` is opt-in, not default** → vibe-delegate auto-injected
  a "no shell for file I/O" preamble; mimo-delegate inherited it but found it
  causes multi-step tasks (e.g. "create files and run tests") to time out with
  0 tool calls — the directive conflicts with mimo's legitimate use of `bash`
  to verify its own work. Mimo's `--dangerously-skip-permissions` already
  prevents the shell-fallback loop the preamble was designed for, so the
  preamble defaults to **off**. Turn it on with `MIMO_WIN_PREAMBLE=on` only if
  you actually observe a shell-fallback loop on some future task.
- **Orchestration chain** → 5 failure points in order: CLI auth → JSON event
  stream parser → token aggregation → git diff → run-log JSON. When a run
  produces unexpected results, work down this list. Full details in
  `SKILL-reference.md`.

---

## Step 1 — Detect workdir

1. `git rev-parse --show-toplevel` in the current directory.
2. If ambiguous or no git repo → ask with `AskUserQuestion`.

---

## Step 2 — Decompose the task

**Critical rule**: keep tasks **atomic and focused** — one objective, one prompt.

| Size | Definition | Max turns | Approach |
|------|-----------|-----------|----------|
| **Trivial** | 1 file, change is obvious and located | — | **Skip delegation — edit directly** |
| **Simple** | 1 file, non-trivial logic or unknown location | 5–8 | 1 mimo call |
| **Medium** | 2–3 related files, 1 objective | 8–12 | 1 structured mimo call |
| **Complex** | >3 files OR business logic OR DB migrations | — | **Break into sub-tasks** |

**Decomposition for complex tasks:**
```
Sub-task 1: Explore / read relevant files (read-only, 5 turns)
Sub-task 2: Implement change A in file X (8 turns)
Sub-task 3: Implement change B in file Y (8 turns)
Sub-task 4: Verify / test (5 turns)
```
→ Check git diff between each sub-task before launching the next.

---

## Step 3 — Write the Mimo prompt

The prompt must be **self-contained**.

**Structure:**
```
Stack: Python/Flask, SQLAlchemy, SQLite
Key files: app.py (routes + fetch), models.py (Entry)

TASK: [one single thing to do, stated as an imperative]

CONSTRAINTS:
- [what must not break]
- [expected format if relevant]

VERIFY: grep for "def function_name" in file.py and confirm it exists.
```

**Formulation rules:**
- One task per prompt — never "also do X and Y"
- Name the exact files to modify
- Include a grep-based verification criterion (not a file re-read)
- Language: English (better Mistral performance)

**Prompt adaptations:**
- **Any task that defines or calls a specific function**: include the exact signature — `def validate(data: dict) -> tuple[bool, list[str]]:`.
- **Write/modify tasks**: append an output format block:
  ```
  OUTPUT FORMAT:
  Modified: <file>
  Does: <one line>
  No other prose.
  ```

### Closed-form replacement prompt (use when the change is precisely known)

When you already know the exact OLD/NEW text — typical for review-comment fixes, planned refactors, or any case where you can grep the literal bytes — **don't describe the bug; give the model the literal blocks and tell it not to explain.** This is the highest-success-rate prompt shape, especially on large files where open-ended prompts time out at 0 tool calls (see Known Limits).

Template (paste literally; the script forwards it via temp file so indentation is safe):
```
File: <path/relative/to/workdir>

Perform exactly N edit operations. Do NOT read the file first. Do NOT explain. Just run the tool calls then stop.

==========
REPLACEMENT 1:

OLD:
<literal block — exact indentation, line endings as in the file>

NEW:
<literal block — exact indentation>

==========
REPLACEMENT 2:
OLD:
...
NEW:
...

After all edit succeed, stop. No verification, no comment.
```

**Use this form when:**
- You already know the exact OLD and NEW text
- File is large (>300 LOC) — open-ended prompts have high timeout risk
- Multiple precise edits in one call (each as its own `REPLACEMENT N` block)

**Do NOT use it when:**
- The model needs to discover the location or design the change → use the open-ended Structure above
- Later replacements depend on earlier model-generated content

**Why it works**: with literal OLD/NEW, the model has no reasoning gap to fill with prose. It functions as a stenographer for `edit`. Evidence carried over from vibe-skill (600-line C# file, same workdir):

| Prompt shape | Model | Tool calls | Duration | Result |
|---|---|---|---|---|
| Open-ended ("fix this bug…") | deepseek-flash | **0** | 188s timeout | empty diff |
| Open-ended (simplified) | deepseek-flash | **0** | 128s timeout | empty diff |
| Closed-form OLD/NEW | mistral-medium-3.5 | 2 | 47s | ✅ 41+/17- |
| Closed-form OLD/NEW | deepseek-flash | 2 | 35s | ✅ 41+/17- (identical) |

The mimo equivalent measurement is TBD; the rule (closed-form OLD/NEW beats open-ended on large files) is model-shape, not model-name, so we expect it to hold on `mimo-auto` too. **Re-measure once you have ≥3 closed-form runs on files >300 LOC** and update this table.

> ⚠️ **Shell safety**: if the prompt contains UTF-8 accented chars, emojis,
> `:` in Python/YAML code, or typographic apostrophes — the mimo-delegate script
> passes them safely via a temp file (`printf %q`). Never interpolate such a prompt
> directly into a bash heredoc.

**Verification — always use grep, not file re-read:**
```
VERIFY: grep for "def extract_labels" in app.py and confirm it exists.
```

---

## Step 4 — Launch Mimo

```bash
~/tools/mimo-delegate "<workdir>" "<prompt>" [max-turns] [agent] [timeout-secs]
```

| Argument       | Default  | Notes                                           |
|----------------|----------|-------------------------------------------------|
| `workdir`      | —        | Absolute path, must exist                       |
| `prompt`       | —        | Self-contained task description                 |
| `max-turns`    | `10`     | Mistral turn limit — hard cap at 12, never more |
| `agent`        | *(none)* | See agent table below                           |
| `timeout-secs` | `180`    | Wall-clock kill timer. Bump to `600` for open-ended prompts on files >300 LOC; closed-form OLD/NEW prompts (Step 3) typically finish in 30-60s and don't need it |
| `--require STR` | *(none)* | Repeatable. Abort before launch if STR is absent in the workdir — pass the `edit` anchor here |

**Available agents:**

| Agent | Use |
|-------|-----|
| *(default)* | General implementation |
| `code-reviewer` | Review only, no changes |
| `planner` | Planning before implementing |
| `code-architect` | Architecture design, read-only |

**Recommended max turns:**
- Read/explore: `5`
- Simple change (1 file): `8`
- Medium change (2–3 files): `12`
- Never exceed `12` — decompose instead

**Background launch:**
```bash
~/tools/mimo-delegate "<workdir>" "<prompt>" 10 > /tmp/mimo_out.txt 2>&1 &
# Monitor with: tail -f /tmp/mimo_out.txt
```

---

## Step 5 — Supervise in real time

The script prints live:
```
=== MIMO START ===
Workdir : /path/to/project
Agent   : (default)
Model   : (mimo default — mimo-auto on free tier)
Turns   : 10 (log-only; mimo manages turn budget)
Timeout : 180s
Prompt  : Stack: Python/Flask. File: app.py ...
==================
  [read]  app.py
  [tool]  edit [OK]  app.py
  [mimo]  Done. Converted date to datetime.date in fetch_data().
Tool calls: 3  |  warns: 0  |  sr_fails: 0
Delegate tokens (run): 4,800  (in: 4,600 / out: 200)  |  cost ~$0.0000
Claude Sonnet 4.6 eq: same tokens would cost ~$0.0168  (mimo free: $0)
=== MIMO DONE (exit: 0) ===
=== SYNTAX OK (1 check(s)) ===

=== UNCOMMITTED CHANGES ===
 app.py | 4 ++--
[log] → ~/.local/share/delegate-runs.jsonl  (4800 tokens, exit 0, 34.2s, saved ~$0.0168 vs Claude)
```

**Mimo never commits.** All changes are left unstaged — `git checkout .` reverts everything if needed.

**Red flags to act on immediately:**

| Flag | Meaning | Action |
|------|---------|--------|
| `[WARN]` | Mimo encountered an error | Read the error, fix manually |
| `[tool]  edit [FAIL]` | UTF-8 match failure | Edit manually with Python `str.replace()` |
| `exit: 1` or non-zero | Mimo failed / did not complete verification | Read diff, correct prompt |
| `Tool calls: 0` + 1000+ output tokens + timeout | Model wrote prose instead of calling tools — open-ended prompt on a large file | Switch to **closed-form OLD/NEW prompt** (Step 3). Do not relaunch the same prompt |
| No `[tool]  file:` lines | `WROTE_NOTHING` — Mimo read but wrote nothing | Do not compensate — fix prompt and relaunch |
| `=== SYNTAX ERRORS ===` | Post-run syntax check failed | **Fix before committing** |
| Same file read 5+ times | Mimo is looping — run likely lost | Abort, check diff, try again |

**Known bugs and workarounds:**

| Bug | Cause | Fix |
|-----|-------|-----|
| Variable declared twice | Mimo doesn't check scope | Grep the variable before relaunching |
| Truncated prompt | Special chars in inline prompt | Script uses temp file — should be fixed |
| Wrote a Python helper just to replace code | Misdiagnosed edit limit | Use edit directly for ASCII code; write only if new content is too long for the prompt |
| Empty run — 0 files changed despite ≥3 tool calls | Multi-edit prompt: first `edit` target not found byte-for-byte | Split into sequential single-change runs; grep target string locally before delegating |
| Free tier quota exhausted | Mimo's `mimo-auto` is fingerprint-throttled | Switch via `/mimo-model-pick anthropic-sonnet` (with a key) or wait for quota reset |

**If exit non-zero:** do not relaunch immediately. Read the diff, understand what was done, fix the prompt.

---

## Step 6 — Iteration

- **Max 3 attempts** per sub-task before escalating to the user.
- Between attempts, **read the git diff** to avoid doubling partial work.
- If Mimo completed ≥50% and crashed: finish the rest manually rather than relaunching.

---

## Step 7 — Report to the user

```
✓ Mimo finished — <1-line summary>

Files modified:
  - path/to/file.ext (+X / -Y lines)

[If problem]:
⚠ <description> — completing manually / relaunching?

Ready to commit?
```

---

## Orchestration rules

- **Decompose before delegating** — one task, one prompt.
- **JSON format always** — `mimo run` runs with `--format json`; never switch to default formatted output (the parser depends on the JSON event stream).
- **Check diff between sub-tasks** — never launch the next one blind.
- **Don't code instead of Mimo** unless Mimo completed ≥50% and crashed.
- **Wall-clock timeout is the only safety cap** — mimo has no `--max-turns`. Default 180s; bump to 600s for open-ended prompts on files >300 LOC. Closed-form OLD/NEW prompts typically finish in 30-60s and don't need it.
- **Grep target before delegating** — `grep -n "exact_target" file.py` before any `edit` prompt. Pass that anchor as `--require "exact_target"` so the delegate aborts before launching if it's gone. Always use grep for VERIFY, not file re-read.
- **Default to mimo-auto** — free tier is fine for inline edits and small refactors. If a run repeatedly hits empty output / quick errors on the same prompt that worked previously, suspect free-tier rate-limiting and switch model via `/mimo-model-pick`.
- **Closed-form > open-ended when the change is known** — if you can write the literal OLD/NEW blocks, use the closed-form template (Step 3) regardless of file size. Open-ended "fix this bug" prompts on files >300 LOC commonly hit 0 tool calls + timeout. Reach for closed-form first; fall back to open-ended only when the model must discover the location or design the change.
- **UTF-8 / emoji in the prompt** → the script handles it via temp file, but test with a short prompt first.
- **After any run that touches imports: grep the import line** — always run `grep "^from X import" file.py` before the next sub-task.
- **edit [OK] ≠ correct change** — always grep the specific changed line, not just check syntax.
- **Provide data structure context** — if a route accesses a DB payload, include the exact field paths (`payload['produit']['nom']`) in the prompt.
- **Reuse existing assets** — for UI tasks, tell Mimo to link existing CSS/JS files. "Use `/static/style.css` and CSS class `bar-row`" is always better than "generate a dark theme".

---

## Run Log

Every run appends one JSON entry to `~/.local/share/delegate-runs.jsonl`.
Log fields and jq queries → see `SKILL-reference.md`.

```bash
~/tools/delegate-report                  # mimo runs only (default)
~/tools/delegate-report --since 7        # last 7 days
~/tools/delegate-report --project myapp  # filter by project
~/tools/delegate-report --fails          # failures only
~/tools/delegate-report --adapt          # failure rates by prompt adaptation
~/tools/delegate-report --all            # all delegates (shared log)
~/tools/delegate-report --delegate opencode  # a specific delegate
```

Or via Claude Code: `/mimo-report [args]`. Log fields and jq queries → `SKILL-reference.md`.

---

## See Also

This skill was ported from [vibe-skill (windows-fix)](https://github.com/KakaruHayate/vibe-skill/tree/windows-fix),
which uses the same orchestration pattern but delegates to Mistral Vibe instead of MiMoCode.
A sister delegate using Gemini CLI also exists: [gemini-skill](https://github.com/pcx-wave/gemini-skill).
All three write to the same `delegate-runs.jsonl` log, so runs are comparable across delegates via `delegate-report --all`.
