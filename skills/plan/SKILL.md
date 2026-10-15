---
name: plan
description: Split a spec (docs/specs/NNN-name.md) into task files for headless implementers, and list the dependency changes the spec needs. Use after the spec skill, before running tasks. Writes no product code.
---

# Plan: from a spec to task files

You split one spec into task files: work orders that headless agents finish on their own. You
also list the dependency changes the whole spec needs. Work in the product repository's root.
You write files under `docs/specs/NNN-name/` only. No product code, no build files.

## How a task is run

Write every task for this:

- It runs in its own git worktree, branched from `main`. The implementer sees the product's
  `AGENTS.md`, the task file and the code; nothing from this conversation.
- Nobody answers its questions. A decision the task leaves open gets made by guessing.
- It is done when `scripts/verify` passes, offline. A reviewer then checks the diff against the
  task's acceptance criteria.
- A task in `depends_on` is merged into `main` before this task starts. Tasks whose `touches`
  overlap can't run at the same time.
- Tasks never add, remove or upgrade a dependency. Those changes land on `main` first (step 5).

## 1. Read

Read the spec, the product's `AGENTS.md` and the documents it points to. If the spec leaves a
behavior question open that a task depends on, settle it with the user now and update the spec.

## 2. Learn the code

Read the code the spec touches: where each change goes, the patterns and tests to copy, what
already exists. For a broad question about unfamiliar code, you can ask the scout, a cheap
read-only agent:

```bash
rd="$FACTORY_HOME/runs/plan-NNN-name/scout-1"; mkdir -p "$rd"     # a new directory per question
cat > "$rd/question.md" <<'EOF'
<one question, and where to start looking if you know>
EOF
"$FACTORY_HOME/bin/agent-run" scout "$PWD" "$rd/question.md" "$rd" && cat "$rd/scout.out.md"
```

Check the lines it cites before you rely on them. If `FACTORY_HOME` isn't set or the call fails,
read the code yourself.

## 3. Agree on the split

Before writing files, show the user the task list: for each task its id, one line of goal,
`touches` and `depends_on`. Adjust until the user agrees. Rules for the split:

- **One session each.** One coherent change, a handful of files. If the goal needs "and", split it.
- **Checkable on its own.** Each task leaves `main` green and adds tests for its own behavior. No
  task depends on a later one to compile or pass.
- **Order honestly.** If a task needs another task's code, it lists it in `depends_on`, even when
  their `touches` don't overlap. Prefer independent tasks where the spec allows it.

## 4. Write the task files

One file per task, `docs/specs/NNN-name/tasks/<id>.md`, in the format of
`$FACTORY_HOME/templates/task.md`. `<id>` is `TTT-short-name`: `TTT` continues after the highest
task number in any `docs/specs/*/tasks/` (ids name branches, so they're unique across specs).
`spec` is the spec's path.

- **Goal:** the outcome in one or two sentences.
- **Context:** the exact files to read first (`path`, or `path:Symbol`), the patterns and tests to
  copy, what exists already. Reference only what is on `main` or what a `depends_on` task creates.
- **Constraints / out of scope:** every decision the implementer would otherwise guess: names,
  signatures, error types and messages, formats, defaults, what must not change. No "consider",
  "if appropriate" or "for example" where a decision belongs.
- **Acceptance criteria:** observable behavior, each item checkable by a test, ending with
  `scripts/verify passes`.
- **`touches`:** every file or directory the task creates or changes, tests included. Keep it
  narrow; it decides what may run in parallel.
- **Report:** keep the template's section.

## 5. List the dependency changes

Write `docs/specs/NNN-name/dependencies.md`: for each change, the exact name and version, add,
upgrade or remove, which tasks need it, and why. Prefer what the product already uses; say why
that isn't enough when you add something. If there are none, write `None.`

Don't edit build files or lockfiles yourself. If the user asks you to draft the change, make it
its own commit on `main` touching only build files and lockfiles, with the package manager's own
command where there is one, then run `scripts/verify`.

## 6. Hand over

Report to the user:

- the tasks, with `depends_on`, and the pairs whose `touches` overlap (they can't run together);
- a suggested order of batches;
- the dependency changes, which must land on `main` before the tasks run;
- the decisions you made that the spec didn't, so the user can check them.

Ask the user to read every task file and judge: could a new contractor do this from the file
alone? When the user approves, commit the spec, `dependencies.md` and the task files together
on `main`. Don't push.
