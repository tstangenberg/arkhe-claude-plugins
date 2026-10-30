#!/usr/bin/env bash
# Orchestrate Gemini, Codex, and Devin shim generation for all arkhe plugins.
#
# Reads .claude-plugin/marketplace.json to enumerate plugins. Runs the three
# Python generators (transpile-commands.py, generate-codex-agents-md.py,
# generate-devin-commands.py), then writes per-plugin Gemini and Codex
# manifests, GEMINI.md context files, Devin .devin-plugin manifests, and
# skills/agents symlinks. Idempotent: re-running produces no diff.
#
# Requires: bash 4+, jq, python3 (3.8+).

set -euo pipefail

# Bash 5.2+ (e.g. Ubuntu 24.04 CI runners) treats a literal `&` in the
# replacement of `${var//pat/repl}` as "the matched text" when the
# patsub_replacement option is on (the default). That corrupts our HTML
# entity escaping below: `${skill_desc//@/&#64;}` would emit `@#64;` instead
# of `&#64;`, diverging from macOS's bash 3.2 output and tripping shim-drift
# CI. Disable it so `&` stays literal on every bash version (the option does
# not exist before 5.2, hence the guard).
shopt -u patsub_replacement 2>/dev/null || true

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
PLUGINS_DIR="$REPO_ROOT/plugins"
GEMINI_ROOT="$REPO_ROOT/.gemini-extensions"
CODEX_ROOT="$REPO_ROOT/.codex-marketplace"
DEVIN_ROOT="$REPO_ROOT/.devin-plugins"
TRANSPILE="$REPO_ROOT/scripts/transpile-commands.py"
CODEX_GEN="$REPO_ROOT/scripts/generate-codex-agents-md.py"
DEVIN_GEN="$REPO_ROOT/scripts/generate-devin-commands.py"
READMES_GEN="$REPO_ROOT/scripts/update-plugin-readmes.py"

err() { printf 'build-shims: %s\n' "$*" >&2; exit 1; }

[[ -f "$MARKETPLACE" ]] || err "marketplace.json not found at $MARKETPLACE"
command -v jq >/dev/null 2>&1 || err "jq is required (brew install jq)"
command -v python3 >/dev/null 2>&1 || err "python3 is required"

# Repo URL baked into generated Devin git-subdir dependency entries.
# Derived from origin so forks produce self-referencing URLs; normalized
# to an https .git URL. Empty when the checkout has no origin remote.
REPO_GIT_URL=$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)
if [[ "$REPO_GIT_URL" == git@* ]]; then
    REPO_GIT_URL=$(printf '%s' "$REPO_GIT_URL" | sed -E 's#^git@([^:]+):#https://\1/#')
fi
if [[ -n "$REPO_GIT_URL" && "$REPO_GIT_URL" != *.git ]]; then
    REPO_GIT_URL="$REPO_GIT_URL.git"
fi
[[ -x "$TRANSPILE" ]] || err "transpile-commands.py not executable: $TRANSPILE"
[[ -x "$CODEX_GEN" ]] || err "generate-codex-agents-md.py not executable: $CODEX_GEN"
[[ -x "$DEVIN_GEN" ]] || err "generate-devin-commands.py not executable: $DEVIN_GEN"
[[ -x "$READMES_GEN" ]] || err "update-plugin-readmes.py not executable: $READMES_GEN"

# Step 1: run Python generators (idempotent; they write their own outputs).
python3 "$TRANSPILE"
python3 "$CODEX_GEN"
python3 "$DEVIN_GEN"
python3 "$READMES_GEN"

# Atomic write: render to temp file, only move into place if content differs.
# Keeps mtimes stable across runs and prevents partial files on crash.
write_if_changed() {
    local dest="$1" tmp
    tmp=$(mktemp "${dest}.tmp.XXXXXX")
    cat >"$tmp"
    chmod 0644 "$tmp"
    if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$dest"
    fi
    # Self-heal mode (no-op when already 0644). Cheap and keeps git happy.
    chmod 0644 "$dest" 2>/dev/null || true
}

# Idempotent symlink: create if missing, replace only if target differs.
# Checkouts with core.symlinks=false (e.g. Windows without symlink
# privilege) materialize links as plain files containing the target path —
# self-heal those into real symlinks so the build stays idempotent.
ensure_symlink() {
    local link_path="$1" target="$2"
    if [[ -L "$link_path" ]]; then
        local current
        current=$(readlink "$link_path")
        [[ "$current" == "$target" ]] && return 0
        rm "$link_path"
    elif [[ -e "$link_path" ]]; then
        if [[ -f "$link_path" && "$(cat "$link_path")" == "$target" ]]; then
            rm "$link_path"
        else
            err "$link_path exists and is not a symlink"
        fi
    fi
    ln -s "$target" "$link_path"
}

# Render a per-plugin GEMINI.md: bootstrap pointer + skill index.
# Reads SKILL.md description fields directly (one-line strip).
render_gemini_md() {
    local plugin="$1"
    local skills_dir="$PLUGINS_DIR/$plugin/skills"
    printf '# %s\n\n' "$plugin"
    printf '> **Bootstrap:** Load `using-arkhe-skills` first — it maps Claude-only tools (`AskUserQuestion`, `TaskCreate`, `EnterPlanMode`, `Skill`, `Agent`) to Gemini equivalents. Install the `core` extension if you have not already.\n\n'
    printf '@../../plugins/core/skills/using-arkhe-skills/SKILL.md\n\n'
    if [[ -d "$skills_dir" ]]; then
        printf '## Skills\n\n'
        local skill_md
        for skill_md in "$skills_dir"/*/SKILL.md; do
            [[ -f "$skill_md" ]] || continue
            local skill_name skill_desc
            skill_name=$(basename "$(dirname "$skill_md")")
            # Pull a single-line `description:` from YAML frontmatter.
            # Extract description from YAML frontmatter. Handles inline
            # values, folded (`>`), and literal (`|`) block scalars by
            # joining indented continuation lines with a single space.
            skill_desc=$(awk '
                BEGIN { fm = 0; in_desc = 0; desc = "" }
                /^---[[:space:]]*$/ {
                    if (fm == 0) { fm = 1; next }
                    if (in_desc && desc != "") print desc
                    exit
                }
                fm == 1 {
                    if (in_desc) {
                        if (/^[[:space:]]/) {
                            line = $0
                            sub(/^[[:space:]]+/, "", line)
                            if (line != "") desc = (desc == "" ? line : desc " " line)
                            next
                        }
                        print desc; exit
                    }
                    if (/^description:/) {
                        val = $0
                        sub(/^description:[[:space:]]*/, "", val)
                        sub(/^"/, "", val); sub(/"$/, "", val)
                        if (val == ">" || val == "|" || val == ">-" || val == "|-") {
                            in_desc = 1; desc = ""
                        } else { print val; exit }
                    }
                }
            ' "$skill_md")
            # Escape '@' in description text. Gemini's ImportProcessor parses
            # bare `@token` patterns as filesystem imports (e.g., Java
            # annotations like @RestController in spring-boot skill descriptions
            # cause ENOENT errors). HTML entity &#64; survives this preprocessor
            # and renders identically for the model.
            local desc_safe="${skill_desc//@/&#64;}"
            printf -- '- **%s** — %s\n' "$skill_name" "${desc_safe:-(no description)}"
        done
        printf '\n'
    fi
    printf '## Commands\n\nSee `commands/` directory for transpiled Gemini TOML commands.\n'
}

# Step 2: per-plugin manifests + symlinks.
# Using `while IFS=... read` with process substitution keeps the loop in the
# parent shell so plugin_count survives. Avoids `mapfile` (Bash 4+; macOS
# ships 3.2).
plugin_count=0
while IFS=$'\t' read -r plugin description; do
    [[ -n "$plugin" ]] || continue
    plugin_json="$PLUGINS_DIR/$plugin/.claude-plugin/plugin.json"
    [[ -f "$plugin_json" ]] || err "missing plugin manifest: $plugin_json"

    version=$(jq -r '.version // "0.0.0"' "$plugin_json")

    # --- Gemini extension ---
    gemini_dir="$GEMINI_ROOT/$plugin"
    mkdir -p "$gemini_dir"
    jq -n --arg name "$plugin" --arg desc "$description" --arg ver "$version" \
        '{name: $name, description: $desc, version: $ver, contextFileName: "GEMINI.md"}' \
        | write_if_changed "$gemini_dir/gemini-extension.json"
    jq -n --arg name "$plugin" --arg desc "$description" --arg ver "$version" \
        '{name: $name, description: $desc, version: $ver}' \
        | write_if_changed "$gemini_dir/plugin.json"
    render_gemini_md "$plugin" | write_if_changed "$gemini_dir/GEMINI.md"
    ensure_symlink "$gemini_dir/skills" "../../plugins/$plugin/skills"

    # --- Codex marketplace ---
    codex_dir="$CODEX_ROOT/$plugin"
    mkdir -p "$codex_dir"
    jq -n --arg name "$plugin" --arg desc "$description" --arg ver "$version" \
        '{name: $name, description: $desc, version: $ver}' \
        | write_if_changed "$codex_dir/plugin.json"
    ensure_symlink "$codex_dir/skills" "../../plugins/$plugin/skills"

    # --- Devin plugin ---
    # .devin-plugins/<p>/ holds a native .devin-plugin/plugin.json (takes
    # precedence over the .claude-plugin fallback), a skills symlink, an
    # agents symlink when the plugin ships agents, and generated
    # devin-commands/<cmd>/SKILL.md wrappers from generate-devin-commands.py.
    devin_dir="$DEVIN_ROOT/$plugin"
    mkdir -p "$devin_dir/.devin-plugin"

    skills_json='["skills"]'
    [[ -d "$devin_dir/devin-commands" ]] && skills_json='["skills","devin-commands"]'

    # Cross-plugin runtime deps surface as optionalPlugins endorsements
    # (allow-list entries; they never auto-install). core's VERIFY UI route
    # and design-intent's /prototype gallery both call devtools'
    # arkhe-preview CLI.
    optional_json='[]'
    if [[ -n "$REPO_GIT_URL" ]]; then
        case "$plugin" in
            core|design-intent)
                optional_json=$(jq -n --arg url "$REPO_GIT_URL" \
                    '[{source: "git-subdir", url: $url, path: ".devin-plugins/devtools"}]')
                ;;
        esac
    fi

    jq -n --arg name "$plugin" --arg desc "$description" --arg ver "$version" \
        --argjson skills "$skills_json" --argjson optional "$optional_json" \
        '{name: $name, version: $ver, description: $desc, skills: $skills}
         + (if ($optional | length) > 0 then {optionalPlugins: $optional} else {} end)' \
        | write_if_changed "$devin_dir/.devin-plugin/plugin.json"
    ensure_symlink "$devin_dir/skills" "../../plugins/$plugin/skills"
    if [[ -d "$PLUGINS_DIR/$plugin/agents" ]]; then
        ensure_symlink "$devin_dir/agents" "../../plugins/$plugin/agents"
    fi
    # bin/ isn't on PATH on Devin, but keep it reachable inside the plugin
    # dir so skills can resolve tools (e.g. devtools' arkhe-preview) by path.
    if [[ -d "$PLUGINS_DIR/$plugin/bin" ]]; then
        ensure_symlink "$devin_dir/bin" "../../plugins/$plugin/bin"
    fi

    plugin_count=$((plugin_count + 1))
done < <(jq -r '.plugins[] | [.name, .description] | @tsv' "$MARKETPLACE")

printf 'build-shims: %d plugins processed\n' "$plugin_count"
