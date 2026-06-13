# Mimo — Reference

Not loaded at runtime. Read this file when troubleshooting, querying logs, or looking up full details for items summarised in SKILL.md.

## Known Limits — Full Details

### 1. UTF-8 / special chars cause `edit` failures
Mimo's `edit` tool matches `oldString` byte-for-byte. Accented chars, curly quotes, or emoji in the anchor → `state.status` returns an error and the run logs a `sr_fails` increment. Use the `--require "anchor"` precheck to abort before launch when the anchor is suspect; for known-tricky strings, restructure the prompt to avoid them or have Mimo `write` the whole file.

### 2. Code duplication bug
Mimo sometimes re-inserts a block already written (off-by-one in its diff logic). Check for duplicate function definitions or repeated class bodies after every run.

### 3. Orchestration chain — 5 independent failure points
`mimo run CLI → JSON event stream parser → token aggregation → git diff → run-log JSON`

| Link | Failure mode | Symptom |
|------|-------------|---------|
| Mimo CLI | Free-tier quota hit, network down, fingerprint blocked | `step_finish` arrives but `tool_use` count = 0, or immediate non-zero exit |
| JSON parser | Mimo changes its event schema (type names, `part` structure) | Tool calls not detected, wrong token count, empty `[mimo]` text lines |
| Token aggregation | `step_finish.tokens` schema change (e.g. `cache.read` moves out of `cache` block) | `tokens_in`/`tokens_out` accumulate to 0 despite normal-looking run |
| git diff | Not a git repo, or Mimo committed mid-run | Wrong file count, misleading stat |
| JSON log | `~/.local/share/` not writable | Silent log skip, `/mimo-report` misses the run |

### 4. Never pass source code through a bash heredoc
Nested quotes, f-strings, or backslashes in inline bash `<< 'PYEOF'` mangle escaping. Use `edit` directly for ASCII code; `write` only if the new content is too long for the prompt. Never write a helper script whose sole job is `str.replace()` on another file.

### 5. HTML tags in the prompt body cause shell redirect errors (exit 127)
Tags like `<div>` are interpreted as file redirections. The delegate script writes the prompt to a temp file (safe), but if you invoke `mimo run` directly with raw HTML in the message arg, it will explode. Always go through `mimo-delegate`.

### 6. Free tier (mimo-auto) is fingerprint-throttled
The free-tier JWT issued by `https://api.xiaomimimo.com/api/free-ai/bootstrap` is tied to a per-machine fingerprint (sha256 of hostname / OS / arch / CPU / username). If you exceed the limit, `step_finish.cost` stays at 0 but the API will return empty content or 4xx-via-CLI. Switch via `/mimo-model-pick anthropic-sonnet` (if you have a key configured via `mimo providers`), or wait.

### 6a. Free tier silent hangs (observed during this port's stress tests, 2026-06-13)
Independently of throttling, **free tier sometimes accepts the prompt but produces zero stdout** — the `mimo run` process sits idle, no JSON events stream, no error message. Reproduced 3+ times during stress tests where the same prompt had succeeded minutes earlier. The wall-clock timeout (5th arg to `mimo-delegate`, default 180s) is what saves the run — it kills mimo and logs `failure_reason=timeout`, tokens=0, tool_calls=0. Mitigation: don't run >2-3 delegations in rapid succession on free tier; on a `timeout` failure, wait 30-60s before retrying or switch model. This is a server-side or CLI-side issue, not something the delegate can detect mid-run.

### 7. No `--max-turns`
Unlike vibe, mimo doesn't expose a turn-budget flag — it manages its own. The 3rd positional arg to `mimo-delegate` is recorded in the log for cross-delegate comparison only. The real safety cap is wall-clock timeout (5th arg, default 180s).

---

## Run Log Fields

Every run appends one JSON entry to `~/.local/share/delegate-runs.jsonl`.

| Field | Type | Description |
|---|---|---|
| `ts` | string | ISO 8601 UTC timestamp |
| `delegate` | string | `"mimo"` |
| `workdir` | string | Absolute project path |
| `project` | string | `basename(workdir)` |
| `prompt_words` | int | Word count of the prompt |
| `agent` | string | Agent used (`"default"`, `"code-reviewer"`, etc.) |
| `max_turns` | int | Recorded for log only; mimo does NOT consume this |
| `timeout_secs` | int | Configured wall-clock timeout in seconds |
| `exit_code` | int | 0=success · 124=timeout · other=error |
| `timed_out` | bool | `true` if `exit_code == 124` |
| `tool_calls` | int | Total tool invocations (`tool_use` events) |
| `files_changed` | int | Files modified (git diff count) |
| `syntax_errors` | int | Python/JS/etc syntax errors detected post-run |
| `duration_secs` | float | Total wall-clock duration |
| `tokens_in` | int | Sum of `step_finish.tokens.input` across all steps |
| `tokens_out` | int | Sum of `step_finish.tokens.output` |
| `tokens_total` | int | `tokens_in + tokens_out` |
| `cost_usd` | float | Sum of `step_finish.cost` (0 on free tier) |
| `cost_claude_eq` | float | Claude Sonnet 4.6 equivalent cost ($3/M in + $15/M out) |
| `model` | string | Active model — defaults to `mimo-auto` |
| `warn_count` | int | `[WARN]` events (tool calls with status ≠ `completed`) |
| `search_replace_fails` | int | `edit` calls that failed (kept name for cross-delegate compat) |
| `wrote_nothing` | bool | `true` if ≥3 tool calls but 0 files changed (backwards compat) |
| `failure_reason` | string | `ok` \| `silent_exit` \| `near_empty` \| `wrote_nothing` \| `timeout` \| `exit_error` \| `syntax_error` \| `sr_fail` \| `warn_only` \| `precheck_abort` |
| `adaptations` | list | Prompt adaptations detected: `contract` \| `output_format` \| `compact` |

---

## Cost estimate methodology

Per run, `mimo-delegate` aggregates tokens and cost **inline from the JSON event stream** —
each `step_finish` event carries `tokens.{input,output,reasoning,cache.{read,write}}` and `cost`.
These are estimates for comparison, not billed amounts.

| Piece | Source / method | Caveat |
|---|---|---|
| Total tokens | Sum of `tokens.input + tokens.output` across all `step_finish` events | Real — mimo's measured count |
| Input vs output split | Sum of `tokens.input` (in) and `tokens.output` (out) separately | Reasoning tokens are not counted in either bucket (mimo's `tokens.reasoning` is reported separately and excluded from the cost line) |
| Cache tokens | `tokens.cache.read` is reported but **excluded from `tokens_in`** | On the free tier (cost=0) this doesn't matter; for paid providers, cache reads are typically billed at a discount, so excluding them yields the same "cost-equivalent input" shape vibe-delegate used |
| Price | Sum of `step_finish.cost` across all events | Free tier → 0. Paid providers (anthropic/, openai/, deepseek/) → real cost computed by mimo itself |
| Claude equivalent | Same in/out tokens priced at $3 / $15 per M | Fixed Sonnet 4.6 reference rate |

Unlike vibe-delegate, there's no separate meta.json read or TOML pricing lookup —
mimo gives us cost directly per step, and we sum it. If a future paid provider's
cost field is missing or mis-typed, the bash log line shows `cost ~$0.0000` and
the `cost_claude_eq` column still works as a savings proxy.

## jq Queries

```bash
# Success rate
jq -r '.exit_code' ~/.local/share/delegate-runs.jsonl | sort | uniq -c

# Total cost vs Claude equivalent
jq -r '[.cost_usd, .cost_claude_eq] | @tsv' ~/.local/share/delegate-runs.jsonl \
  | awk '{c+=$1; e+=$2} END {printf "Spent: $%.4f  Claude eq: $%.4f  Saved: $%.4f\n", c, e, e-c}'

# Runs with edit failures (search_replace_fails kept for cross-delegate compat)
jq 'select(.search_replace_fails > 0)' ~/.local/share/delegate-runs.jsonl

# Empty runs (wrote nothing despite tool calls)
jq 'select(.wrote_nothing == true)' ~/.local/share/delegate-runs.jsonl

# Compare mimo vs vibe on the same project
jq 'select(.project == "myapp") | {delegate, exit_code, tokens_total, cost_usd}' \
   ~/.local/share/delegate-runs.jsonl
```
