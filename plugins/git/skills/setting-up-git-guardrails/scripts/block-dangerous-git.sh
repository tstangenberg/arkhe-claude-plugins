#!/usr/bin/env bash
# PreToolUse hook: block destructive git commands before Claude Code runs them.
# Exit 2 blocks the tool call and returns stderr to the agent.
# Fails closed: if jq is missing or the input can't be parsed, the command is blocked.
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq is required by the git guardrail hook. Install jq or remove the hook." >&2
  exit 2
fi

if ! COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOCKED: git guardrail could not parse the tool input." >&2
  exit 2
fi

DANGEROUS_PATTERNS=(
  "git push"
  "git reset --hard"
  "git clean -fd"
  "git clean -f"
  "git branch -D"
  "git checkout \."
  "git restore \."
  "push --force"
  "reset --hard"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if printf '%s\n' "$COMMAND" | grep -qE "$pattern"; then
    echo "BLOCKED: '$COMMAND' matches dangerous pattern '$pattern'. The user has prevented you from doing this." >&2
    exit 2
  fi
done

exit 0
