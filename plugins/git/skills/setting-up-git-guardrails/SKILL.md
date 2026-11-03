---
name: setting-up-git-guardrails
description: Set up Claude Code hooks that block destructive git commands (push, reset --hard, clean, branch -D, checkout/restore of all files) before they run. Use when user runs /setting-up-git-guardrails, wants to prevent destructive git operations, add git safety hooks, or block git push or reset in Claude Code.
disable-model-invocation: true
---

# Setting Up Git Guardrails

Installs a `PreToolUse` hook that intercepts Bash tool calls and blocks dangerous git commands before they execute. Opt-in: nothing is installed until you run this skill.

## What Gets Blocked

- `git push` (all variants, including `--force`)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git branch -D`
- `git checkout .` / `git restore .`

When blocked, the agent receives a message saying the user has prevented the command.

**Warning:** this also blocks the git plugin's own push-based commands (`/create-pr`, `/release`). Run those yourself while the guardrail is active, or remove the hook first.

## Steps

### 1. Check prerequisites

The hook needs `jq`. Run `command -v jq`. If it's missing, stop and tell the user to install it. The hook fails closed without it, which blocks all Bash calls.

### 2. Ask scope

Ask whether to install for **this project only** (`.claude/settings.json`) or **all projects** (`~/.claude/settings.json`).

### 3. Copy the hook script

Copy [scripts/block-dangerous-git.sh](scripts/block-dangerous-git.sh) to:

- **Project**: `.claude/hooks/block-dangerous-git.sh`
- **Global**: `~/.claude/hooks/block-dangerous-git.sh`

Make it executable with `chmod +x`.

### 4. Register the hook

Merge into the settings file's `hooks.PreToolUse` array. If the file exists, keep its other settings.

**Project** (`.claude/settings.json`), exec form so the path needs no quoting:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash",
            "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/block-dangerous-git.sh"]
          }
        ]
      }
    ]
  }
}
```

**Global** (`~/.claude/settings.json`), shell form so `~` expands:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

### 5. Ask about customization

Ask whether to add or remove patterns. Edit the copied script's `DANGEROUS_PATTERNS` array.

### 6. Verify

```bash
echo '{"tool_input":{"command":"git push origin main"}}' | bash <path-to-script>; echo "exit=$?"
echo '{"tool_input":{"command":"git status"}}' | bash <path-to-script>; echo "exit=$?"
```

The first should print `BLOCKED` to stderr and exit 2. The second should exit 0.

## Known Limits

- **Substring matching:** a command that only mentions a pattern, such as `echo "git push"`, is blocked too.
- **Bash only:** the hook matches the `Bash` tool. It doesn't stop other tools that change git state.
- **No allowlist:** to permit one command, remove the hook or edit the script.
