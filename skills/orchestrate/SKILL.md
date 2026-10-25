---
name: orchestrate
description: Run a planned spec's task files through the factory in batches (bin/fan-out, bin/collect), triage the results, and bring the user only tasks ready for review, questions and escalations; after the user's review, sync it (bin/review sync). Use after the plan skill, in the product repo. Never merges.
---

# Orchestrate: from task files to merge-ready branches

You run one spec's tasks through the factory and triage what comes back. The scripts do the
work: `bin/fan-out` runs a batch, `bin/collect` reports on it. You decide what runs together,
read the results, fix what you can, and bring the user only what needs them. Work in the product
repository's root, on `main`. `FACTORY_HOME` is the factory's directory; if it isn't set, stop and
ask the user to start the session through the factory's `bin/start`.

**You never merge, push or rebase yourself.** The user reviews and merges. The factory's scripts
push task branches to the product's forge and merge what the user approves; you only run them.
You may commit to `main` only edited task files (step 4), and append to
`$FACTORY_HOME/docs/factory-log.md`. The product's forge is `"$FACTORY_HOME/bin/forge" name
"$PWD"`: `local`, or a git host such as `github`.

## 1. Read the plan

Read the spec, its `docs/specs/NNN-name/tasks/*.md` (the frontmatter's `depends_on` and
`touches`) and `docs/specs/NNN-name/dependencies.md`.

- Every dependency change listed there must be on `main` already. If one isn't, stop and tell
  the user; no task runs before it lands.
- Find each task's state:
  - **merged:** no `factory/<id>` branch, and `git log main --format=%s` has a subject starting
    with `factory: <id>` (a pull request squashed on a forge keeps that subject, plus ` (#<n>)`). A task merged another
    way won't show; ask the user about tasks that look done in the code.
  - **waiting for the user:** a branch `factory/<id>` exists. `"$FACTORY_HOME/bin/review" status`
    shows where each one's review stands.
  - **to run:** everything else.
- The product checkout must be clean and on `main`. If not, stop and say so.
- On a forge other than `local`, `main` must also be pushed: a task's pull request is against
  the remote's `main`, and the forge refuses to open one that would include local-only commits.
  If `git rev-list --count <remote>/main..main` (after a fetch) isn't 0, ask the user to push
  `main`; that includes your own task-file commits.

## 2. Build the next batch

A task can run when every task in its `depends_on` is merged. From those, pick a batch where no
two tasks' `touches` overlap: the same file, or one path inside another's directory. At most 3
tasks per batch unless the user says otherwise (parallel workers share the account's quota).
Prefer tasks that unblock the most others.

Show the user the batch and what comes after it in one short list, then start it. Don't wait for
approval unless something is unusual (a task you rewrote, a re-queue, a batch of one because of
overlaps).

## 3. Run it

```bash
"$FACTORY_HOME/bin/fan-out" "$PWD" docs/specs/NNN-name/tasks/<id>.md ...
```

Give the task paths in full; a glob expands in your current directory. A batch takes from minutes
to an hour. If your shell tool has a time limit, run it in the background and wait to be told it
finished; don't poll. Then:

```bash
"$FACTORY_HOME/bin/collect"
```

## 4. Triage each task

Read the `collect` output first, then the files it points to for the cases below. Open a run's
`*.events.jsonl` only when nothing else explains what happened.

- **green / approve:** it's ready for the user's review (on a forge, `collect` shows its pull
  request; no `review:` line there means the submit failed: read the end of `run-task.log`). Read
  the review's minor notes and the report's decisions. Most notes are style. A note that names a
  real gap (an acceptance criterion untested, a spec rule broken, a case a later task must
  handle) goes to the user with the task, together with where it should be fixed: in this branch
  (the user sends it as a remark), or in a named later task file (edit it as below).
- **green / changes-needed:** the reviewer still had findings after the last fix round. Read the
  last `review-<n>.md`. Bring it to the user with your judgment: merge as is, or rewrite the task
  and re-queue. After a rework (the run dir has `user-review-<n>.md`), the task is already back
  in the user's review: the reviewer disagrees with the user's remarks, and the user decides.
- **green / error:** the review itself failed. Read `run-task.log`. Bring it to the user.
- **red:** read the end of `verify.log` and `REPORT.md`. Decide the cause:
  - the task file was unclear, wrong or contradicted the code: rewrite it and re-queue;
  - it needs a dependency change: either rewrite the task so it doesn't, or bring the change to
    the user (it lands on `main` like any other dependency change, then the task is re-queued);
  - anything else (a hard problem, an environment failure, a broken `main`): bring it to the user.
- **closed** (in `bin/review status`): the user re-queued it in `bin/review`, or closed its pull
  request, because the task file or the spec was wrong. Read its `user-review-*.md` (and on a
  forge, the pull request's last comments) to find out what. A wrong or incomplete task file:
  rewrite it and re-queue, as below. A requirement that changes: bring it to the user, it's a
  spec change.
- **Open questions in a report:** answer them from the spec if you can. If the answer changes
  the work, put it in the task file as a constraint and re-queue; otherwise tell the user what
  you answered. Questions only the user can answer go to the user.

**Rewriting a task file:** change only what caused the failure, keep its id, and commit it
alone on `main` with the message `tasks: <id>: <what changed>`. Before re-queuing, keep the
failed attempt's work and remove its worktree and branch, or `fan-out` refuses the task:

```bash
wt="${PWD}-wt/<id>"; rd=<the task's run dir>
git -C "$wt" add -A && git -C "$wt" diff --cached main > "$rd/abandoned.patch"
git worktree remove --force "$wt" && git branch -D factory/<id>
```

Re-queue a task at most once on your own. If it fails again, it goes to the user.

## 5. Log every failure

For each task that was red, ended changes-needed or error, was re-queued, or was approved with a
real gap, append one line to `$FACTORY_HOME/docs/factory-log.md`, in the format its header
describes. Take the harness and model from `calls.log` and `$FACTORY_HOME/config/routing.json`.
Describe the failure in factory terms (no product domain, code or stack; the log is in the
factory) and point to the run dir for the details. Write the cause as you understand it; leave
`fix:` as `pending` unless you already fixed it (such as a rewritten task file). The `retro` skill turns these lines into factory changes. Don't
commit the factory repo.

## 6. Report to the user

Show only:

- **Ready for review:** each task, one line on what it does, and any real gap from step 4. On the
  local forge, the user reviews them with `"$FACTORY_HOME/bin/start" "$FACTORY_HOME/bin/review"` in the product
  repo (approve merges and cleans up; remarks go back to the implementer). On a forge, give each
  pull request's link: the user approves and merges there, or requests changes.
- **Questions** only the user can answer, each with your proposed answer.
- **Escalations:** what failed, why you think it failed, and what you suggest.
- **Next:** the next batch, and what it waits for.

## 7. After the user's review

When the user says they reviewed:

1. Sync. It reworks the tasks the user requested changes on (in the background of your shell
   tool if it has a time limit, like `fan-out`), and for merged tasks updates `main`, verifies it
   in an offline sandbox and removes their worktrees and branches:
   ```bash
   "$FACTORY_HOME/bin/review" sync
   ```
   It acts only on this machine's tasks, never on other people's branches or pull requests. If it
   says `main` is red or couldn't be updated, stop and show the user; don't start a batch on a
   red `main`. A worktree it left in place (changes besides `REPORT.md`) goes to the user.
2. Triage the reworked tasks with `bin/collect <task-run-dir>` as in step 4, and the `closed`
   ones as in step 4. Report as in step 6.
3. Go back to step 2 until every task is merged. Then tell the user the spec is done.
