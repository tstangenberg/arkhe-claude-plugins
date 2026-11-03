---
name: using-arkhe-skills
description: Use when starting any conversation - establishes how arkhe skills bootstrap on Claude Code, Antigravity CLI (agy) / Gemini CLI, Codex CLI, and Devin, and maps Claude-only tools (AskUserQuestion, TaskCreate, EnterPlanMode, the Skill tool, the Agent tool) to their cross-platform equivalents
---

<SUBAGENT-STOP>
If dispatched as a subagent to execute a specific task, skip this skill.
</SUBAGENT-STOP>

# Using arkhe Skills Across Platforms

arkhe plugins ship the same `SKILL.md` files across CLI harnesses. This bootstrap establishes how to access skills and how to translate platform tool names into equivalent operations on Claude Code, Antigravity CLI (`agy`), Gemini CLI, Codex CLI, and Devin.

## How to Access Skills

- **Claude Code:** Use the `Skill` tool. When invoked, the skill content is loaded and presented to follow directly.
- **Antigravity CLI (`agy`):** Skill metadata (name + description) is auto-loaded into the system prompt at session start. When triggers fire, use `view_file` to load `skills/<skill-name>/SKILL.md` from the plugin directory, then follow its instructions.
- **Gemini CLI (Legacy):** Skill metadata is loaded into system prompt. Use `read_file` to load `skills/<skill-name>/SKILL.md`.
- **Codex CLI:** Skill index and trigger phrases are inlined in `AGENTS.md` at install time. Follow the skill body directly when a trigger phrase fires.
- **Devin:** Plugin skills register as `/<plugin>:<skill>` slash commands at install time. Invoke the `skill` tool with the plugin-namespaced name (e.g. `core:sdlc-develop`) or the slash form directly. Skill references of the form `<plugin>:<skill>` inside skill bodies resolve the same way.

## Platform Tool Mapping

arkhe SKILL.md files reference core agent primitives. On each platform, substitute the equivalent operation from this table.

| Primitive / Claude tool | Antigravity CLI (`agy`) equivalent | Gemini CLI (Legacy) equivalent | Codex CLI equivalent | Devin equivalent |
|---|---|---|---|---|
| `AskUserQuestion` | `ask_question` (native interactive modal with chip UI options) | Ask a plain-text question with numbered choices and await reply. | Plain-text question with numbered choices. | `ask_user_question` tool (never available to subagents) |
| `TaskCreate` / `TaskUpdate` | `manage_task` or inline TODO list rendered on each turn | Inline TODO list rendered on each turn | Inline TODO list rendered on each turn | `todo_write` tool |
| `EnterPlanMode` / `ExitPlanMode` | Native `--mode plan` / `accept-edits` mode | Announce plan mode and gate writes on approval | Announce plan mode and gate writes on approval | Native plan mode |
| Skill tool (`Skill`) | `view_file` on `skills/<name>/SKILL.md` | `read_file` on `skills/<name>/SKILL.md` | Skill content inlined in `AGENTS.md` | `skill` tool / `/<plugin>:<skill>` |
| Agent tool (`subagent_type`) | `invoke_subagent` / `define_subagent` (native background/concurrent subagent execution) | Inline agent prompt into current session | Inline agent prompt into current session | `run_subagent` with profile `<plugin>:<agent>` (CLI/Desktop only — not cloud sessions) |
| `TodoWrite` | — | — | — | `todo_write` tool |
| `Bash` | — | — | — | `exec` tool |
| `WebFetch` / `WebSearch` | — | — | — | `webfetch` / `web_search` tools |

## Command Naming Across Platforms

Commands ship from the same `plugins/<plugin>/commands/<name>.md` source on every platform, but the slash-command syntax differs:

| Platform | Form | Example |
|---|---|---|
| Claude Code | `/<plugin>:<command>` (plugin-namespaced) | `/core:think` |
| Antigravity CLI (`agy`) / Gemini CLI | `/<command>` (or `agy plugin` commands) | `/think` |
| Codex CLI | Trigger phrase in chat (no slash) | "think through whether to use Postgres or Redis" |
| Devin | `/<plugin>:<command>` (wrapper skill, plugin-namespaced) | `/core:think` |

On Devin, commands ship as generated wrapper skills under `.devin-plugins/<plugin>/devin-commands/` — `/core:develop` is a thin skill that delegates to `core:sdlc-develop`, identical invocation to Claude.

When this skill or other arkhe docs refer to `core:think`, `core:debug`, etc., resolve them through this table — same command, platform-specific invocation.

## Subagent-Heavy Commands

Six arkhe commands dispatch subagents on Claude Code and Antigravity CLI (`agy`). On Devin they dispatch natively too — plugin agents load as `<plugin>:<agent>` subagent profiles (CLI and Devin Desktop only; in cloud sessions plugin agents are unavailable and the work runs inline). On legacy Gemini and Codex CLI, they run inline with the agent's prompt collapsed into the command body.

The affected commands:

- `core:debug` (with `--deep`)
- `core:think`
- `core:research`
- `core:double-check` (with `--deep`)
- `spring-boot:spring-review`
- `spring-boot:verify-upgrade`

## Instruction Priority

1. **User's explicit instructions** (CLAUDE.md, GEMINI.md, AGENTS.md, direct requests) — highest priority
2. **arkhe skills** — override default system behavior where they conflict
3. **Default system prompt** — lowest priority

If `CLAUDE.md`, `GEMINI.md`, or `AGENTS.md` says "do not use TDD" and a skill says "always use TDD," follow the user's instructions. The user is in control.

## Where Skills Live

- **Canonical source:** `plugins/<plugin>/skills/<skill>/SKILL.md`
- **Claude Code:** loaded via `.claude-plugin/marketplace.json`
- **Antigravity CLI / Gemini CLI:** loaded via `plugins/<plugin>/plugin.json` or `.gemini-extensions/<plugin>/plugin.json` (skills directory is a symlink to the canonical source)
- **Codex CLI:** loaded via `.codex-marketplace/<plugin>/AGENTS.md` (skill index synthesized at build time; full content via symlinked `skills/`)
- **Devin:** loaded via `.devin-plugins/<plugin>/.devin-plugin/plugin.json` (skills and agents are symlinks to the canonical sources; commands are generated wrapper skills in `devin-commands/`)

Skill bodies are not duplicated across platforms. One file, cross-platform support.
