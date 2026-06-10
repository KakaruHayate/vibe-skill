---
name: vibe
description: Delegate focused coding work to the local Mistral Vibe CLI via ~/tools/vibe-delegate, then supervise and review the resulting git diff. Use when the user explicitly asks to use vibe, delegate work, save Codex tokens with Vibe, run a Vibe usage report/status/model override, or when a non-trivial coding task is suitable for a focused external implementation pass. Do not use for trivial one-file edits where the exact change is already obvious.
---

# Vibe

Use the local `vibe` CLI as a coding delegate. Codex remains the orchestrator: choose the task boundary, write the prompt, run the delegate, inspect the diff, fix any issues, and report the outcome.

## Preconditions

- `~/tools/vibe-delegate` must exist.
- `vibe` must be on PATH.
- Run from a git worktree when possible so changes can be reviewed with `git diff`.
- On Windows, use this skill's PowerShell wrapper: `scripts/run-vibe.ps1`.

## Decision Rule

Delegate only focused coding tasks.

- Skip Vibe for a trivial exact edit in one known file.
- Use one Vibe run for a simple or medium task with one objective.
- Split complex work into subtasks and inspect `git diff` between runs.
- Use at most 12 turns per run; prefer 5 for exploration, 8 for simple edits, 12 for medium edits.

If Vibe fails three times on the same subtask, stop delegating and finish manually or ask the user.

## Workflow

1. Detect the workdir with `git rev-parse --show-toplevel`. If there is no repo, use the user's active project directory if clear.
2. Inspect enough code to make the Vibe prompt self-contained.
3. Write a concise English prompt with stack, files, task, constraints, and grep-based verification.
4. Save the prompt to a UTF-8 temp file.
5. Run `scripts/run-vibe.ps1`.
6. Read Vibe output, then inspect `git diff --stat` and `git diff`.
7. Verify the changed behavior with focused tests or grep checks.
8. Report files changed, verification, and any manual fixes.

## Prompt Shape

Prefer this structure:

```text
Stack: <language/framework>
Key files:
- <path>: <purpose>

TASK:
<one imperative objective>

CONSTRAINTS:
- Preserve <important behavior/API/style>
- Modify only <files or area>

TOOL CONTRACT:
- Use ONLY write_file and search_replace tools to create or modify files.
- Do NOT use shell commands (bash, command, run_command, powershell, cmd) to write, create, or copy files.
- If write_file or search_replace fails twice on the same file, STOP and report the error. Do not fall back to shell.
- Use forward-slash paths.

VERIFY:
grep for "<specific changed symbol or line>" in <file> and confirm it exists.

OUTPUT FORMAT:
Modified: <file>
Does: <one line>
No other prose.
```

Use one task per prompt. Name exact files when known. Include exact function signatures when relevant.

Keep the `TOOL CONTRACT` block for any task that creates or modifies files. It prevents a common Windows failure mode where Vibe's file tool is denied and the model tries `cmd.exe` shell fallbacks such as `mkdir -p`, PowerShell heredocs, or `echo <html>`, burning the turn budget without changing files.

For prompts involving HTML, XML, JSX, shell metacharacters, emojis, or non-ASCII text, never interpolate prompt text directly into a shell command. Save the prompt to a UTF-8 file and use `scripts/run-vibe.ps1`.

For precise edits where the old and new text are already known, use a closed-form replacement prompt instead of asking Vibe to reason:

```text
File: <relative/path>

Perform exactly N search_replace operations. Do NOT read the file first. Do NOT explain. Just run the tool calls then stop.

TOOL CONTRACT:
- Use ONLY search_replace for these replacements.
- Do NOT use shell commands.
- If any search_replace fails twice, STOP and report the failing OLD block.

==========
REPLACEMENT 1:

OLD:
<literal old block>

NEW:
<literal new block>
```

Before using a closed-form prompt, grep the old anchor locally and pass it as `-Require` to the wrapper.

Use closed-form OLD/NEW prompts whenever the exact replacement is known, especially for files larger than 300 lines. Open-ended "fix this bug" prompts on large files can produce `Tool calls: 0` and an empty diff.

## Running Vibe

From PowerShell:

```powershell
$promptFile = Join-Path $env:TEMP "vibe-prompt.txt"
Set-Content -LiteralPath $promptFile -Encoding UTF8 -Value @"
<prompt here>
"@

& "<skill-dir>\scripts\run-vibe.ps1" `
  -Workdir "<absolute project path>" `
  -PromptFile $promptFile `
  -MaxTurns 8 `
  -TimeoutSeconds 180
```

For closed-form edits:

```powershell
& "<skill-dir>\scripts\run-vibe.ps1" `
  -Workdir "<absolute project path>" `
  -PromptFile $promptFile `
  -MaxTurns 8 `
  -TimeoutSeconds 180 `
  -Require "<literal OLD anchor>"
```

Use `-Agent code-reviewer` only for review-only passes. On Windows, leave `-Agent` unset for normal edits so `vibe-delegate` can default to `auto-approve`.

Do not disable `VIBE_WIN_PREAMBLE` on Windows. The delegate script injects an additional no-shell file I/O preamble; the explicit `TOOL CONTRACT` in the prompt is a second guard for the same failure mode.

## Reports And Status

If the user asks for a Vibe report, run `~/tools/delegate-report` through Git Bash and relay its output. Map common wording to flags:

- "last 7 days" or "7d": `--since 7`
- "last 30 days" or "30d": `--since 30`
- "project NAME": `--project NAME`
- "fails", "failures", or "bugs": `--fails`
- "adaptations": `--adapt`
- "all delegates": `--all`
- "delegate NAME": `--delegate NAME`

Also report a market-price equivalent for direct GPT-5.5 work when token fields are available in `~/.local/share/delegate-runs.jsonl`.

Default market-price basis:

- Model: `gpt-5.5`
- Source: official OpenAI API pricing page, checked 2026-06-10
- Standard short-context price: input `$5.00 / 1M tokens`, cached input `$0.50 / 1M tokens`, output `$30.00 / 1M tokens`
- Long-context price: input `$10.00 / 1M tokens`, cached input `$1.00 / 1M tokens`, output `$45.00 / 1M tokens`
- Default calculation: use standard short-context input/output rates unless the user explicitly asks for long-context, Batch, Flex, Priority, or cached-token accounting.
- Cache assumption: delegate logs do not split cached vs uncached input tokens, so treat all input tokens as uncached unless a cached-token field is later added.

Use `scripts/market-price-report.ps1` for a repeatable local calculation:

```powershell
& "<skill-dir>\scripts\market-price-report.ps1" -SinceDays 1 -Project "<project-name>"
```

For a single run, calculate:

```text
gpt5_5_market_usd = (tokens_in / 1_000_000 * 5.00) + (tokens_out / 1_000_000 * 30.00)
saved_vs_gpt5_5 = gpt5_5_market_usd - cost_usd
ratio = gpt5_5_market_usd / cost_usd
```

If the user asks for Vibe status, report:

```text
Auto-vibe: ON|OFF
Model: <alias> (override) OR Model: (config default)
```

Check `~/.local/share/vibe-auto.flag` and `~/.local/share/vibe-model.flag`.

For model override requests:

- Set override: write the alias to `~/.local/share/vibe-model.flag`.
- Clear override: delete `~/.local/share/vibe-model.flag`.

Known aliases from the local setup include `deepseek-flash`, `mistral-medium-3.5`, `devstral-small`, and `local`.

## Failure Handling

Act on these Vibe output signals:

- `search_replace [FAIL]`: inspect the target and edit manually or use a more exact anchor.
- `Tool calls: 0` plus timeout: rewrite as closed-form OLD/NEW or split the task.
- no file changes: do not assume success; inspect output and relaunch only with a clearer prompt.
- syntax errors: fix before reporting completion.
- repeated reads or shell fallback loops: stop the run, inspect diff, and narrow the prompt.

Vibe never commits. Leave changes unstaged unless the user asks otherwise.
