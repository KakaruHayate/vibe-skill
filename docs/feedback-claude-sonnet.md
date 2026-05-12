# Feedback from Claude Sonnet 4.6
# After an intensive session (~25 Vibe runs on a real project)

## Token economics

Vibe's internal turns (file reads, search/replace attempts) consume **Mistral tokens**,
not Claude tokens. Claude only receives the compressed final output (~500–1500 tokens/run).

Example: a task with 6 reads of an 800-line file = ~4800 tokens on Mistral's side, 0 on Claude's.
Real advantage on exploratory/implementation tasks. Neutral or slightly negative if Vibe
fails and produces long error output that comes back into Claude's context.

---

## Frequent bugs observed (for Vibe to fix if possible)

### 1. search_replace fails on UTF-8 / emojis
Most frequent bug of the session. As soon as `old_string` contains accented characters
(É, à, œ), typographic apostrophes ('), or emojis (🤝, 🌿), the match fails silently.
Vibe reports "SEARCH/REPLACE blocks failed" and either gives up or attempts a full file
rewrite (risky).

**Workaround (Claude side):** use `python3` with `str.replace()` for files with French text or emojis.

**Suggestion:** normalize old_string to NFC/NFD before matching, or use semantic diffing
rather than exact byte matching.

### 2. Duplicated code at end of file
Observed twice: Vibe reads a file, writes a block, re-reads to verify, and inserts the
same block a second time at the end. Result: broken syntax.

**Likely cause:** during verification, Vibe doesn't recognize that the content it just
wrote is already there, and inserts it again.

**Suggestion:** before inserting new code, grep for a unique marker (function name, block ID)
to check if it already exists in the file.

### 3. Variable re-declaration
`const labels = ...` declared twice in the same JS scope. Same root cause as #2.
Vibe doesn't analyze scope before writing.

### 4. Excessive re-reading of the same file
Vibe sometimes reads the same file 5–8 times in a 10-turn run, wasting turns.
Repeated reads add nothing if the file hasn't changed between reads.

**Suggestion:** implement a "file already read" cache within the current run.
If the file hasn't been modified since the last read, use the in-memory version.

### 5. Partial verification
Vibe declares "VERIFIED" after reading a 20-line excerpt of an 800-line file.
It doesn't see what it hasn't read. This produces false "DONE" signals that hide
problems outside the read window.

**Suggestion:** for verification, have Vibe grep for the target pattern rather than
re-reading the whole file.

### 6. Shell breakage via inline prompt
When the prompt contains `:` followed by a space (e.g. in a Python dict or YAML),
the bash heredoc can break. Result: prompt is silently truncated and Vibe works on
an incomplete instruction.

**Claude side:** the `vibe-delegate` script now writes the prompt to a temp file via
`printf '%q'` — this covers most cases. For very long prompts with embedded code,
verify the first `[vibe]` output line matches your expectation before trusting the result.

---

## What Claude improved in vibe-delegate (already done)

1. Prompt passed via temp file for long/special-char prompts
2. Automatic post-run syntax check (`py_compile` + `node --check`)
3. Better `[write]` vs `[tool]` distinction in output
4. Explicit `[tool]  search_replace [FAIL]` when a match fails

---

## Suggestions for Vibe itself

- Before any `write_file`, grep for the function/variable name to detect if it already
  exists → prevents duplicates
- Limit re-reads of unchanged files to 1 per run
- Add automatic syntax validation on modified files before declaring "done"
  (`python3 -m py_compile`, `node --check`)
- For verifications: use grep/search rather than full file re-read

---

## What works well (keep it)

- The "1 atomic task = 1 run" pattern is exactly the right granularity
- Streaming output with [read]/[write]/[tool] lines is very readable for orchestration
- Mistral turns not impacting Claude's context is a genuine value
- The `printf %q` fallback in the script cleanly handles inline prompt injection
- The `git diff --stat` at the end of each run is the most useful artifact
