---
name: plan
description: Split a spec (docs/specs/NNN-name.md, or a story on the product's issue tracker) into task files for headless implementers, and list the dependency changes the spec needs. Use after the spec skill, before running tasks. Writes no product code.
---

# Plan: from a spec to task files

You split one spec into task files: work orders that headless agents finish on their own. You
also list the dependency changes the whole spec needs. Work in the product repository's root.
You write files under `docs/specs/NNN-name/` only. No product code, no build files.

**With an issue tracker** (`"$FACTORY_HOME/bin/tracker" name "$PWD"` isn't `none`), the spec is a
story on the board, and the tasks go there too. The differences are marked *With a tracker*
below. The story's key is what the user gives you; `"$FACTORY_HOME/bin/tracker" items "$PWD"`
lists the stories with their statuses. Plan only a story in `open`, `blocked` or `refined`: one in
`todo` is being planned by the factory, and one in `in-progress` has tasks running. Don't call
`bin/tracker comments`: it marks comments as taken, so the factory's planner would never see
them; the user tells you what you need.

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

Read the spec, the product's `AGENTS.md` and the documents it points to. *With a tracker:* the
spec is `"$FACTORY_HOME/bin/tracker" read "$PWD" <story>`, and on a re-plan, its current tasks are
`items "$PWD" <story>`, each read by its key. If the spec leaves a
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
- **Small enough to plan at once.** If the split needs more than 8 tasks, or the spec holds
  outcomes the user could ship one at a time, say so and propose smaller specs, each with its own
  goal, before going on.

## 4. Write the task files

One file per task, `docs/specs/NNN-name/tasks/<id>.md`, written like
`$FACTORY_HOME/templates/task.md`. It starts with a `# ` heading naming the task in a few words,
then the fields, one per line, each starting with its key: `id:`, `spec:`, `depends_on:` and
`touches:` (lists comma-separated, `[]` for none). No frontmatter `---` lines. `<id>` is `NNN-TT-short-name`: `NNN` is the spec's number,
`TT` numbers its tasks from `01`, and `short-name` is kebab-case (`004-02-csv-export`). Ids name
branches, so the spec's number keeps them unique across specs.
`spec` is the spec's path.

*With a tracker:* write the files to `$FACTORY_HOME/runs/plan-<story key, lowercased>-session/`,
not the product repo; empty it first, since every file in it is published. The id is `<story key, lowercased>-TT-short-name`, and `story: <key>`
replaces `spec:`. On a re-plan, a task that stays keeps its id: the tracker's task is updated in
place.

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

*With a tracker,* there is no `dependencies.md`: list the changes in your report (step 6), and
the user lands them on `main` before moving the story to `in-progress`.

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

*With a tracker,* when the user approves, publish the tasks to the story and mark it planned;
nothing is committed:

```bash
"$FACTORY_HOME/bin/tracker" publish "$PWD" <story> "$FACTORY_HOME/runs/plan-<story, lowercased>-session"
"$FACTORY_HOME/bin/tracker" move "$PWD" <story> refined
```

`publish` creates or updates one task per file and cancels the story's tasks whose id is gone.
The user starts them by moving the story to `in-progress`, once the dependency changes are on
`main`.
