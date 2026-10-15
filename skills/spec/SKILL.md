---
name: spec
description: Interview the user about a feature or change and write it down as a spec in the product repo (docs/specs/NNN-name.md). Use when the user wants to specify work before it is planned into tasks. Asks questions; writes no code.
---

# Spec: from an idea to a written spec

You turn the user's idea into a spec: a short document that says what the feature must do, for
whom, and where its edges are. The `plan` skill turns the spec into task files later, and
headless agents implement them without being able to ask anything. So every question about
behavior must be answered here, by the user, or be listed as open.

Work in the product repository's root. You write one file, the spec. No code, no task files, no
build or dependency changes.

## 1. Learn the ground

Before asking anything, read the product's `AGENTS.md` and the documents it points to, the
existing specs in `docs/specs/`, and the code the feature will touch. Don't ask what the code
can answer; ask what only the user can decide.

## 2. Interview

Ask a few questions per round, most important first. With each question, give the answer you
would choose and why, so the user can just confirm. Cover:

- **Goal:** what problem it solves, and why now.
- **Users and callers:** who or what uses it: people, other modules, external systems.
- **Behavior:** the main flow, inputs and outputs, formats, defaults.
- **Edge cases and errors:** empty, missing, invalid, too large, concurrent, failing dependencies;
  what the user or caller sees in each case.
- **Constraints:** compatibility, performance, security, data, what must not change.
- **Non-goals:** what this deliberately doesn't do.
- **Done:** how the user will judge that it works.

Say so when an answer is vague, contradicts an earlier one or the code, or makes the feature much
bigger than the goal needs, and suggest the smaller version. If the feature probably needs a new
dependency, note it; the `plan` skill decides it.

Stop when every behavior question is answered, or the user chose to leave it open.

## 3. Write the spec

Path: `docs/specs/NNN-name.md`. `NNN` is the next three-digit number after the highest existing
`docs/specs/NNN-*` (start at `001`); `name` is a short kebab-case name.

```markdown
# NNN: Title

## Goal
## Users and callers
## Behavior
## Edge cases and errors
## Constraints
## Non-goals
## Done when
Feature-level checks the user will make.
## Open questions
Anything still undecided, or "none".
```

Write decisions, not discussion: "returns 404 when the id is unknown", not "we talked about
404". Name existing files, types and functions where they matter. Keep it as short as the
feature allows.

## 4. Hand over

Show the user the path and the decisions you filled in yourself. Don't commit: the spec is
committed together with its task files once the user has approved the plan. The next step is
the `plan` skill on this spec.
