<!-- Suggested GitHub topics: claude-code, llm-tools, mimocode, mimo, ai-coding, shell, developer-tools -->

# mimo-skill (mimo branch of vibe-skill)

![MIT License](https://img.shields.io/badge/license-MIT-blue.svg) ![Shell](https://img.shields.io/badge/language-Shell-green.svg) ![Claude Code skill](https://img.shields.io/badge/-Claude%20Code%20skill-CC785C)

**Claude orchestrates. MiMoCode does the heavy lifting. You review the diff.**

This branch ports [vibe-skill](https://github.com/KakaruHayate/vibe-skill/tree/windows-fix) — a Claude Code skill that delegates coding tasks to a separate CLI agent — over to **[MiMoCode](https://github.com/XiaomiMiMo/MiMo-Code)** and its free `mimo-auto` tier. All the orchestration pattern (decompose → atomic prompt → grep-verify → diff-review) is kept; only the underlying CLI swaps.

The motivation is that Xiaomi MiMo currently offers a free tier (`mimo-auto`), which means every delegated coding turn runs at **$0** on the user's side, while Claude still sees only ≈500–1500 orchestration tokens per run.

## Quick start

```bash
# 1. Install MiMoCode itself (one-time)
npm install -g @mimo-ai/cli            # provides the `mimo` command

# 2. Drop this repo into your Claude Code skills directory.
#    On Windows: %USERPROFILE%\.claude\skills\mimo\
#    On Linux/macOS: ~/.claude/skills/mimo/
git clone -b mimo https://github.com/KakaruHayate/vibe-skill.git ~/.claude/skills/mimo

# 3. Put the delegate scripts where SKILL.md expects them.
mkdir -p ~/tools
ln -sf ~/.claude/skills/mimo/tools/mimo-delegate.win ~/tools/mimo-delegate.win
ln -sf ~/.claude/skills/mimo/tools/mimo-delegate     ~/tools/mimo-delegate
ln -sf ~/.claude/skills/mimo/tools/delegate-report   ~/tools/delegate-report
```

Then restart Claude Code. The slash commands `/mimo`, `/mimoon`, `/mimooff`, `/mimostatus`, `/mimo-report`, `/mimo-model-pick`, `/mimo-model-clear` become available.

## Commands

| Command | Effect |
|---|---|
| `/mimo <instruction>` | Delegate the task to MiMoCode. Claude decomposes, writes the prompt, supervises the run, reviews the diff. |
| `/mimoon` | Auto-mode ON — every coding request is routed through `/mimo` without typing it. |
| `/mimooff` | Auto-mode OFF — coding tasks handled by Claude directly. |
| `/mimostatus` | Show auto-mode status + active model override. |
| `/mimo-report` | Token / cost / failure stats from the shared run log. Supports `--since N`, `--project NAME`, `--fails`, `--adapt`, `--all`, `--delegate NAME`. |
| `/mimo-model-pick <alias>` | Override the model. Aliases: `auto`, `anthropic-sonnet`, `anthropic-opus`, `openai-gpt5`, `deepseek-v3`. |
| `/mimo-model-clear` | Drop the override; revert to `mimo-auto`. |

## What happens during a `/mimo` call

1. Claude reads `SKILL.md`, decomposes the task into an atomic prompt
2. `mimo-delegate.win` (on Windows) or `mimo-delegate` (Unix) launches:
   `mimo run --format json --dangerously-skip-permissions "$PROMPT_CONTENT"`
3. The delegate parses the JSON event stream live, printing `[tool] write` / `[tool] edit` / `[mimo] <text>` lines and accumulating tokens + cost
4. After mimo exits the script prints `git diff --stat`, runs syntax checks on changed files, and appends one JSON entry to `~/.local/share/delegate-runs.jsonl`
5. Claude reads the diff, summarizes, asks you whether to commit

The skill never commits on your behalf — changes are left unstaged so `git checkout .` reverts everything if you want to retry.

## Shared run log

The log file `~/.local/share/delegate-runs.jsonl` is **shared** with other delegate skills (`vibe-skill`, `gemini-skill`, etc.). Every entry has a `delegate` field so `/mimo-report --delegate mimo` scopes correctly. Drop in multiple delegate skills side by side and `delegate-report --all` will give you a cross-delegate comparison.

## Status

This branch is a fresh port from `windows-fix`. The orchestration rules (closed-form OLD/NEW prompts, atomic decomposition, grep-then-delegate, etc.) are inherited from vibe-skill; their mimo-specific evidence tables are TBD pending real-world workload runs.

Known things that **work** (verified during this port's smoke test, 2026-06-13):
- `mimo run --format json --dangerously-skip-permissions` produces a clean event stream
- Token and cost aggregation from `step_finish.tokens` / `step_finish.cost`
- `write` and `edit` tool detection (mimo's tool surface, analogous to vibe's `write_file`/`search_replace`)
- Syntax check + git diff + shared run log
- Free tier `mimo-auto` returns `cost:0` per step — confirmed

Known things that are **untested**:
- Large-file (>300 LOC) open-ended prompt failure modes
- Free-tier rate limits on sustained use
- `/mimo-model-pick <non-default>` with a real paid provider configured via `mimo providers`

## See also

- Upstream skill: [KakaruHayate/vibe-skill](https://github.com/KakaruHayate/vibe-skill) (Mistral Vibe delegate)
- Underlying CLI: [XiaomiMiMo/MiMo-Code](https://github.com/XiaomiMiMo/MiMo-Code) (Xiaomi MiMo's open-source coding agent)

## License

MIT. See [LICENSE](LICENSE) in the upstream `vibe-skill` repo.
