---
name: configuring-issue-tracker
description: Configure this repo for issue-driven workflows: pick the issue tracker (GitHub, GitLab, or local markdown), set the triage label vocabulary, and record the domain doc layout. Use when user runs /configuring-issue-tracker, says "set up issue tracker", "configure triage", "set up triage labels", "where do issues live", or before first use of the triaging-issues skill.
disable-model-invocation: true
---

# Configuring the Issue Tracker

Scaffold the per-repo configuration that the `triaging-issues` skill assumes:

- **Issue tracker**: where issues live (GitHub by default; GitLab and local markdown are also supported)
- **Triage labels**: the strings used for the five canonical triage roles
- **Domain docs**: where `GLOSSARY.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Read whatever exists; don't assume:

- `git remote -v` and `.git/config`: is this a GitHub or GitLab repo? Which host?
- `AGENTS.md` and `CLAUDE.md` at the repo root: does either exist? Is there already an `## Agent skills` section?
- `GLOSSARY.md` and `GLOSSARY-MAP.md` at the repo root. If the legacy `CONTEXT.md` / `CONTEXT-MAP.md` exists, offer to `git mv` it to its `GLOSSARY` name and rewrite those names in `docs/agents/domain.md`.
- `docs/adr/` and any `src/*/docs/adr/` directories (the `doc` plugin's `adr` skill writes to `docs/adr/`)
- `docs/agents/`: does this skill's prior output already exist?
- `.scratch/`: a sign that a local-markdown tracker convention is already in use
- Monorepo signals: a `pnpm-workspace.yaml`, a `workspaces` field in `package.json`, or a populated `packages/*` with its own `src/`. Their absence means single-context, which is almost every repo.

### 2. Present findings and ask

Summarise what's present and what's missing. Then take the sections in order: one section, one answer, then the next.

Lead each section with the recommended answer so the user can accept it in a word. Give a one-line explainer only when the choice genuinely branches; skip a section when exploration already settled it (Section C when there's no monorepo).

**Section A: Issue tracker.**

> Explainer: The "issue tracker" is where issues live for this repo. The `triaging-issues` skill reads from and writes to it. It needs to know whether to call `gh issue create`, `glab issue create`, or write a markdown file under `.scratch/`. Pick the place you actually track work for this repo.

Default posture: if a `git remote` points at GitHub, propose GitHub. If it points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. Otherwise, or if the user prefers, offer:

- **GitHub**: issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab**: issues live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Local markdown**: issues live as files under `.scratch/<feature>/` (good for solo projects or repos without a remote)
- **Other** (Jira, Linear, etc.): ask the user to describe the workflow in one paragraph; record it as freeform prose

Record the choice in `docs/agents/issue-tracker.md`. The GitHub and GitLab templates carry a "PRs/MRs as a request surface" flag, defaulted **off**. Leave it off and don't raise it: a user who wants external PRs in the triage queue can flip the flag later.

A GitHub or GitLab tracker needs a reachable repo. If no `git remote` points at that host, get the repo URL from the user and wire it up (`git init` if needed, `git remote add origin <url>`) before going further. Done when `gh repo view` / `glab repo view` prints the project from inside this directory; if not, stop and tell the user what's missing.

**Section B: Triage label vocabulary.** Always runs: the `triaging-issues` skill ships in this plugin, so it is always present.

Ask exactly one question:

> Do you want to keep the default triage labels? (recommended: **yes**)

The defaults are the five canonical roles, each label string equal to its role name: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. The category roles `bug` and `enhancement` match the labels this repo's issue templates already apply, so they need no mapping. On **yes**, write the defaults as-is. Only on **no**, usually because the tracker already uses other names (e.g. `bug:triage` for `needs-triage`), collect the overrides so `triaging-issues` applies existing labels instead of creating duplicates.

**Section C: Domain docs.** Default to **single-context** (one `GLOSSARY.md` + `docs/adr/` at the repo root). Write it without asking.

Offer **multi-context** (a root `GLOSSARY-MAP.md` pointing to per-context `GLOSSARY.md` files) only when exploration found monorepo signals. Then confirm the layout.

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block for whichever of `CLAUDE.md` / `AGENTS.md` is being edited
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, and `docs/agents/domain.md`

Let them edit before writing.

### 4. Write

**Pick the file to edit:**

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, ask which one to create; don't pick for them.

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa). If an `## Agent skills` block already exists, update it in place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout: "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

When Section B ran on GitHub or GitLab, create each configured label the tracker lacks (`gh label create` / `glab label create`).

Then write the docs files using the seed templates in this skill folder:

- [issue-tracker-github.md](./issue-tracker-github.md): GitHub issue tracker
- [issue-tracker-gitlab.md](./issue-tracker-gitlab.md): GitLab issue tracker
- [issue-tracker-local.md](./issue-tracker-local.md): local-markdown issue tracker
- [triage-labels.md](./triage-labels.md): label mapping
- [domain.md](./domain.md): domain doc consumer rules and layout

For "other" trackers, write `docs/agents/issue-tracker.md` from scratch using the user's description.

### 5. Done

Tell the user setup is complete and that the `triaging-issues` skill will now read these files. They can edit `docs/agents/*.md` directly later; re-run this skill only to switch trackers or start over.

## Related

- [triaging-issues](../triaging-issues/SKILL.md): the consumer of this configuration
- `/resolve-review`: handles PR review comments, separate from issue triage
