# Phase 5: Summary

**Goal**: Document what was accomplished

**Model tier**: None (direct output)

---

## Actions

### 0. Sync tasks.md Acceptance Criteria

Before verifying completion, synchronize task status to tasks.md:

1. Read `{spec_path}/tasks.md`
2. Use `TaskList` to get all tasks and their status
3. For each task with status `completed`:
   - Find the corresponding `### T-XX:` section in tasks.md
   - Locate the "#### Acceptance Criteria" subsection
   - Replace all `- [ ]` with `- [x]` within that section
4. Use `Edit` tool to update tasks.md with the changes
5. Log: "Synced acceptance criteria: X checkboxes marked complete across Y tasks"

**Note:** This ensures tasks.md serves as a complete record of completed work, useful for handoffs and documentation.

### 1. Update Domain Glossary

Sync the project's domain vocabulary with what was built. This is a safety net: terms resolved during Phase 1 and Phase 2 should already be in the glossary (the `domain-modeling` skill records them inline), and this step catches any that were missed.

**Skip** when the `doc` plugin's `domain-modeling` skill isn't installed, and log: "Glossary update skipped: domain-modeling skill not available."

1. **Find the glossary.** Look for `GLOSSARY-MAP.md` at the repo root (multi-context) or `GLOSSARY.md` (single context). If neither exists, continue: `domain-modeling` creates one when there's a term to record.
2. **Collect candidate terms** from:
   - `{spec_path}/spec.md`: requirements and any terms defined in Phase 1
   - `{spec_path}/plan.md`: domain concepts named in the architecture
   - Public names added or renamed in this feature's diff (types, aggregates, events) that the glossary doesn't define
3. **Invoke the `domain-modeling` skill** with the candidate list. It adds terms that are specific to the project's domain, flags any that conflict with an existing definition, and offers an ADR only for decisions that are hard to reverse, surprising without context, and the result of a real trade-off.
   - **Under `--auto`**, pass this instruction along with the candidate list: "Autonomous mode: do not ask questions. Leave conflicting terms unchanged and report each conflict and each ADR you would offer in your final message."
4. **Under `--auto`**, record each reported conflict under "Next Steps" in the completion summary, and leave the glossary unchanged for those terms.
5. **Add changed glossary and ADR files** to the "Files Modified" list in the summary.
6. Log: "Glossary: X terms added, Y conflicts flagged, Z ADRs offered."

Implementation details never go into the glossary. If a candidate is only a code-level name (a helper, a config key), leave it out.

### 2. Final Tasks Verification

**Task tracking confirmation:**
1. Use `TaskList` to verify all tasks are marked `completed`
2. If any tasks remain `in_progress` or `pending` (should not occur after Step 4.2 gate):
   - Use `TaskUpdate` to mark them completed if the work was verified during Phase 4
   - Log a warning if tasks were completed but not updated during implementation

**spec.md confirmation:**
1. Read `{spec_path}/spec.md`
2. Confirm all acceptance criteria are marked complete

### 3. Provide Completion Summary

Generate summary in this format:

```markdown
## Development Complete

**Feature:** [what was requested]
**Plan:** [path to saved plan]
**Status:** Complete | Partial | Blocked

### What Was Built
- [Key deliverable 1]
- [Key deliverable 2]
- [Key deliverable 3]

### Files Modified
- `path/to/file1.ts` - [what changed]
- `path/to/file2.ts` - [what changed]
- `path/to/file3.ts` - [what changed]

### Validation Results
- Quality gates: [PASS/issues per wave]
- Wave review: [verdicts and notes from both stages]
- RULE ZERO: [N/6 checks passed]

### Verification Steps
1. [How to test the feature]
2. [Commands to run]
3. [Expected behavior]

### Next Steps

**Always include testing recommendations** (pull from `testing_recommendations` if set in Phase 3, otherwise generate based on implemented files):

- [ ] **Unit tests** for:
  - [hook/utility name] (`path/to/file`)
  - [hook/utility name] (`path/to/file`)
- [ ] **Integration tests** for:
  - [API endpoint/data flow] (`path/to/file`)
- [ ] **E2E tests** for:
  - [user flow description] (if UI work was done)

**Other follow-up items:**
- [Recommended follow-up actions]
- [Related features to consider]
- [Technical debt to address]
```

### 4. Update Spec Status

Update `{spec_path}/spec.md` status to "Complete".

### 5. Save Project Learnings (Persistent Memory Pattern)

Evaluate whether discoveries from this feature should persist as project memory.

**Auto-evaluate candidates from:**
- Architecture trade-offs from Phase 2 (why option A over B)
- Gotchas discovered during implementation (framework limitations, API quirks)
- Domain knowledge from research phase (if Step 2a-res was conducted)
- Integration patterns established between existing and new code

**Filter criteria (only save if):**
- Not derivable from reading the code or git history
- Would be useful for future features in this project
- Represents a decision with non-obvious reasoning

**If candidates found**, use `AskUserQuestion`:
- **header**: "Project Learnings"
- **question**: "{N} learnings identified from this feature. Save to project memory?"
- **options**:
  - { label: "Save all", description: "Write each as a project-type memory file" }
  - { label: "Review first", description: "Show candidates, select which to save" }
  - { label: "Skip", description: "Don't save any memories" }

**Gate: Tier 3** (auto-skip with `--auto`; no memories saved in autonomous mode)

**Response handling:**
- **Save all**: For each learning, write a memory file:
  ```markdown
  ---
  name: {feature-slug}-{learning-topic}
  description: {one-line description}
  type: project
  ---

  {Learning content}

  **Why:** {motivation or constraint}
  **How to apply:** {when this should shape future decisions}
  ```
  Then add a pointer to `MEMORY.md`.
- **Review first**: Present each candidate, let user approve/reject individually, save approved ones
- **Skip**: No memories saved

**If no candidates found**: Skip silently, no user interaction.

### 6. Status Document Sync Suggestion

After the completion summary, check if the project has roadmap status documents:

1. Glob for `docs/PROJECT-STATUS.md` or check `.arkhe.yaml` for `roadmap.status_file`
2. If a status document is found, append to the completion summary:

```markdown
### Status Documents
Project status documents may need updating after this feature.
Run `/roadmap:roadmap update --incremental` to sync PROJECT-STATUS.md.
```

This is a suggestion only — do NOT auto-execute the roadmap update.

---

## Verification Record (RULE ZERO)

RULE ZERO was verified with **fresh evidence** at the Quality & Completion Gate (Step 4.2) before entering Phase 5. This section records the confirmed state for audit purposes.

**Evidence-verified at gate approval (all fresh, not cached):**
- [x] All tasks marked `completed` in tasks.md (read from disk)
- [x] All FR-XXX requirements have file:line implementation evidence
- [x] Acceptance criteria mapped to code with file:line references
- [x] Files actually modified — `git diff --stat` output captured
- [x] Tests pass — test suite output captured with pass/fail counts
- [x] No placeholder code — grep output: 0 matches for TODO/FIXME/NotImplementedError
- [x] Subagent/review recommendations implemented (not just analyzed)

**Evidence artifacts:**
- `git diff --stat` output at gate approval
- Test suite output at gate approval (pass/fail counts, exit code)
- Placeholder grep output at gate approval
- Two-stage wave review verdicts with file:line references

_If any items were noted as exceptions during gate approval, they are documented in the gate log._

---

## Output

Phase 5 produces:
- Completion summary
- Updated spec status
- Verification steps
- Next steps recommendations
- Project learnings saved to memory (if applicable)

**End of SDLC Pipeline**
