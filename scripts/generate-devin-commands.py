#!/usr/bin/env python3
"""Transpile Claude .md commands to Devin wrapper skills.

Walks every plugins/<plugin>/commands/*.md and emits
.devin-plugins/<plugin>/devin-commands/<name>/SKILL.md.

Devin's plugin model has no commands/ concept — skills are the only
invocable unit, surfaced as /<plugin>:<skill> slash commands. Each
generated wrapper skill carries the command's name, description, and
argument-hint so /<plugin>:<command> keeps working verbatim; the body is
the command body unchanged (arkhe command bodies already delegate to the
underlying skill, which resolves by its plugin-namespaced name on Devin).

Commands whose name collides with a same-plugin skill are skipped: the
skill already owns /<plugin>:<name> (e.g. doc:rfc, design-intent:prototype).

Subagent-heavy commands (the six identified in spec 004) get a Devin note
instead of an inlined agent body — plugin agents load natively as
<plugin>:<agent> subagent profiles, so no degradation is needed. The note
is skipped in cloud sessions, where plugin subagents are unavailable.

The whole devin-commands/ tree is regenerated from scratch each run, so
renamed or removed commands never leave stale wrappers. Idempotent:
re-running produces no diff. Stdlib only, Python 3.8+.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Dict, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGINS_DIR = REPO_ROOT / "plugins"
OUTPUT_ROOT = REPO_ROOT / ".devin-plugins"

DEVIN_NOTE = (
    "> **Note (Devin):** subagent dispatch in this command maps to the "
    "`run_subagent` tool with profile `{plugin}:{agent}` — plugin agents "
    "load natively in the CLI and Devin Desktop (not in cloud sessions)."
)

# Commands that dispatch subagents on Claude. Maps a command path
# (relative to repo root) to the subagent profile it invokes.
SUBAGENT_HEAVY: Dict[str, Tuple[str, str]] = {
    "plugins/core/commands/debug.md":               ("core", "systematic-debugger"),
    "plugins/core/commands/think.md":               ("core", "deep-think-partner"),
    "plugins/core/commands/research.md":            ("core", "deep-researcher"),
    "plugins/core/commands/double-check.md":        ("core", "code-reviewer"),
    "plugins/spring-boot/commands/spring-review.md":   ("spring-boot", "spring-boot-reviewer"),
    "plugins/spring-boot/commands/verify-upgrade.md":  ("spring-boot", "spring-boot-upgrade-verifier"),
}


# ---------------------------------------------------------------------------
# YAML frontmatter parsing (manual; stdlib only).
# Mirrors the fallback approach in scripts/transpile-commands.py.
# ---------------------------------------------------------------------------

def parse_frontmatter(content: str) -> Tuple[Dict[str, str], str]:
    """Parse YAML frontmatter and return (fields, body).

    Returns ({}, content) if no frontmatter is found.
    """
    if not content.startswith("---"):
        return {}, content

    match = re.match(r"^---\n(.*?)\n---\n?", content, re.DOTALL)
    if not match:
        return {}, content

    frontmatter_text = match.group(1)
    body = content[match.end():]

    fields: Dict[str, str] = {}
    current_key: Optional[str] = None
    current_value: list = []
    block_scalar: Optional[str] = None  # '>' folded, '|' literal

    def store() -> None:
        if current_key is None:
            return
        if block_scalar == ">":
            text = " ".join(line.strip() for line in current_value if line.strip())
        elif block_scalar == "|":
            text = "\n".join(current_value)
        else:
            text = "\n".join(current_value)
        fields[current_key] = text.strip()

    for line in frontmatter_text.split("\n"):
        if ":" in line and not line.startswith((" ", "\t")):
            store()
            key, _, value = line.partition(":")
            current_key = key.strip()
            value = value.strip()
            if value in (">", "|", ">-", "|-"):
                block_scalar = value[0]
                current_value = []
            else:
                block_scalar = None
                current_value = [value] if value else []
        elif current_key is not None:
            current_value.append(line)

    store()
    return fields, body


# ---------------------------------------------------------------------------
# SKILL.md emission
# ---------------------------------------------------------------------------

def unquote(value: str) -> str:
    """Strip one layer of matching surrounding quotes from a frontmatter value."""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def quote_yaml(value: str) -> str:
    """Quote a scalar for YAML output (double-quoted, minimal escaping)."""
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def render_skill_md(fields: Dict[str, str], body: str, devin_note: Optional[str]) -> str:
    lines = ["---"]
    lines.append(f"name: {fields['name']}")
    if fields.get("description"):
        lines.append(f"description: {quote_yaml(fields['description'])}")
    if fields.get("argument-hint"):
        lines.append(f"argument-hint: {quote_yaml(fields['argument-hint'])}")
    # Commands are user-invoked; the underlying skill keeps its own
    # auto-invoke triggers. Prevent the model from firing wrappers itself.
    lines.append("triggers:")
    lines.append("  - user")
    lines.append("---")
    lines.append("")
    if devin_note:
        lines.append(devin_note)
        lines.append("")
    lines.append(body)
    return "\n".join(lines)


def write_if_changed(path: Path, content: str) -> bool:
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    if not PLUGINS_DIR.is_dir():
        sys.stderr.write(f"error: {PLUGINS_DIR} not found\n")
        return 1

    counts: Dict[str, Tuple[int, int]] = {}
    changed_total = 0
    expected: set = set()
    for plugin_dir in sorted(PLUGINS_DIR.iterdir()):
        if not plugin_dir.is_dir():
            continue
        plugin_name = plugin_dir.name
        commands_dir = plugin_dir / "commands"
        if not commands_dir.is_dir():
            continue

        generated = 0
        skipped = 0
        for md_path in sorted(commands_dir.glob("*.md")):
            command_name = md_path.stem

            # A same-named skill already owns /<plugin>:<name> on Devin.
            if (plugin_dir / "skills" / command_name / "SKILL.md").is_file():
                skipped += 1
                continue

            content = md_path.read_text(encoding="utf-8")
            fm, body = parse_frontmatter(content)
            rel_path = md_path.relative_to(REPO_ROOT).as_posix()

            note = None
            if rel_path in SUBAGENT_HEAVY:
                note_plugin, note_agent = SUBAGENT_HEAVY[rel_path]
                note = DEVIN_NOTE.format(plugin=note_plugin, agent=note_agent)

            fields = {
                "name": command_name,
                "description": unquote(fm.get("description", "").strip()),
                "argument-hint": unquote(fm.get("argument-hint", "").strip()),
            }
            skill_md = render_skill_md(fields, body.strip() + "\n", note)

            output_path = (
                OUTPUT_ROOT / plugin_name / "devin-commands"
                / command_name / "SKILL.md"
            )
            expected.add(output_path)
            if write_if_changed(output_path, skill_md):
                changed_total += 1
            generated += 1

        counts[plugin_name] = (generated, skipped)

    # Prune wrappers for renamed/removed commands so the tree never goes stale.
    pruned = 0
    if OUTPUT_ROOT.is_dir():
        for commands_root in OUTPUT_ROOT.glob("*/devin-commands"):
            if not commands_root.is_dir():
                continue
            for stale in commands_root.rglob("SKILL.md"):
                if stale not in expected:
                    stale.unlink()
                    pruned += 1
            # Remove command dirs left empty by pruning.
            for child in sorted(commands_root.iterdir()):
                if child.is_dir() and not any(child.iterdir()):
                    child.rmdir()
            if not any(commands_root.iterdir()):
                commands_root.rmdir()

    for plugin, (generated, skipped) in counts.items():
        suffix = f", {skipped} skill-owned" if skipped else ""
        print(f"[{plugin}] {generated} command skills generated{suffix}")
    total = sum(g for g, _s in counts.values())
    total_skipped = sum(s for _g, s in counts.values())
    print(
        f"total: {total} command skills; {total_skipped} skipped (skill-owned); "
        f"{changed_total} files written; {pruned} pruned"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
