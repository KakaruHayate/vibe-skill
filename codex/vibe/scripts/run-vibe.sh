#!/usr/bin/env bash
set -euo pipefail

PROMPT_FILE="${1:?Prompt file required}"
DELEGATE="${2:?Delegate script required}"
WORKDIR="${3:?Workdir required}"
MAX_TURNS="${4:-10}"
AGENT="${5:-}"
TIMEOUT_SECS="${6:-180}"
shift 6 || true

if [ "$AGENT" = "__VIBE_DEFAULT_AGENT__" ]; then
  AGENT=""
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "ERROR: prompt file does not exist: $PROMPT_FILE" >&2
  exit 1
fi

if [ ! -f "$DELEGATE" ]; then
  echo "ERROR: delegate script does not exist: $DELEGATE" >&2
  exit 1
fi

PROMPT_CONTENT="$(cat "$PROMPT_FILE")"

exec "$DELEGATE" "$WORKDIR" "$PROMPT_CONTENT" "$MAX_TURNS" "$AGENT" "$TIMEOUT_SECS" "$@"
