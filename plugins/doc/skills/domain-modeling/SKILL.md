---
name: domain-modeling
description: Build and sharpen a project's domain model (GLOSSARY.md, with GLOSSARY-MAP.md for multi-context repos) as you design. Use when discussing codebase terminology, challenging or sharpening domain terms, writing or editing a GLOSSARY.md or GLOSSARY-MAP.md, resolving ambiguous language like "account" or "cancellation", or deciding whether a choice deserves an ADR.
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline: challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* `GLOSSARY.md` for vocabulary is not this skill: that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## File structure

Most repos have a single context:

```
/
├── GLOSSARY.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `GLOSSARY-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── GLOSSARY-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── GLOSSARY.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── GLOSSARY.md
│       └── docs/adr/
```

Create files lazily: only when you have something to write. If no `GLOSSARY.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, the `adr` skill creates it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `GLOSSARY.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account': do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?"

### Update GLOSSARY.md inline

When a term is resolved, update `GLOSSARY.md` right there. Capture each term as soon as it resolves. Use the format in [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md). Done when the term is in `GLOSSARY.md` and any conflict with an existing entry has been raised with the user.

Keep `GLOSSARY.md` to glossary entries only: each term's definition and the synonyms it replaces. Implementation details, specs, and scratch notes belong elsewhere.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. When one qualifies, hand off to the [`adr` skill](../adr/SKILL.md) (`create <title>`), which handles numbering, templates, and the index in `docs/adr/`.

## Choosing single or multi-context

The skill infers which structure applies:

- If `GLOSSARY-MAP.md` exists, read it to find contexts
- If only a root `GLOSSARY.md` exists, single context
- If neither exists, create a root `GLOSSARY.md` lazily when the first term is resolved

When multiple contexts exist, infer which one the current topic relates to. If unclear, ask.

### Creating the map

Create `GLOSSARY-MAP.md` only when the repo has, or is about to have, multiple contexts. Signals:

- The user names distinct bounded contexts (e.g. "ordering and billing are separate")
- The same term means different things in two areas of the code
- A root `GLOSSARY.md` exists and a second context appears

Base the context split on the domain's language and on what the user confirms, not on directory names alone.

Before creating the map, confirm with the user:

1. The context names and their directories (e.g. `src/ordering/`)
2. How the contexts relate: shared types, events, or ownership

Then:

1. Create `GLOSSARY-MAP.md` in the Contexts and Relationships format from [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md).
2. Create each context's `GLOSSARY.md` in its directory.
3. Ask what to do with the existing root `GLOSSARY.md`. The usual choice is to move each term into the context it belongs to. A term used by several contexts can stay in the root file as a shared glossary, which the map should then list as a context.
4. Keep `docs/adr/` at the root for system-wide decisions. Context-specific ADRs go in `<context>/docs/adr/`, created through the `adr` skill.

Create the map only with every context it lists already in place: each listed context has its own `GLOSSARY.md`. Done when every listed context has its file.
