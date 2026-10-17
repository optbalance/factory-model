---
name: orchestrate
description: Run a planned spec's task files through the factory in batches (bin/fan-out, bin/collect), triage the results, and bring the user only merge-ready branches, questions and escalations. Use after the plan skill, in the product repo. Never merges.
---

# Orchestrate: from task files to merge-ready branches

You run one spec's tasks through the factory and triage what comes back. The scripts do the
work: `bin/fan-out` runs a batch, `bin/collect` reports on it. You decide what runs together,
read the results, fix what you can, and bring the user only what needs them. Work in the product
repository's root, on `main`. `FACTORY_HOME` is the factory's directory; if it isn't set, stop and
ask the user to start the session through the factory's `bin/start`.

**You never merge, push or rebase.** The user merges. You may commit to `main` only edited task
files (step 4), and append to `$FACTORY_HOME/docs/factory-log.md`.

## 1. Read the plan

Read the spec, its `docs/specs/NNN-name/tasks/*.md` (the frontmatter's `depends_on` and
`touches`) and `docs/specs/NNN-name/dependencies.md`.

- Every dependency change listed there must be on `main` already. If one isn't, stop and tell
  the user; no task runs before it lands.
- Find each task's state:
  - **merged:** `git log main --format=%s` has the line `factory: <id>`. A task merged another
    way won't show; ask the user about tasks that look done in the code.
  - **waiting for the user:** a branch `factory/<id>` exists.
  - **to run:** everything else.
- The product checkout must be clean and on `main`. If not, stop and say so.

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

- **green / approve:** read the review's minor notes and the report's decisions. Most notes are
  style. A note that names a real gap (an acceptance criterion untested, a spec rule broken, a
  case a later task must handle) goes to the user with the branch, together with where it should
  be fixed: in this branch, or in a named later task file (edit it as below).
- **green / changes-needed:** the reviewer still had findings after the last fix round. Read the
  last `review-<n>.md`. Bring it to the user with your judgment: merge as is, or rewrite the task
  and re-queue.
- **green / error:** the review itself failed. Read `run-task.log`. Bring it to the user.
- **red:** read the end of `verify.log` and `REPORT.md`. Decide the cause:
  - the task file was unclear, wrong or contradicted the code: rewrite it and re-queue;
  - it needs a dependency change: either rewrite the task so it doesn't, or bring the change to
    the user (it lands on `main` like any other dependency change, then the task is re-queued);
  - anything else (a hard problem, an environment failure, a broken `main`): bring it to the user.
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

- **Ready to merge:** each branch, one line on what it does, and any real gap from step 4. Give
  the commands; parallel branches share a base, so each is rebased onto the `main` that already
  has the earlier ones:
  ```bash
  git -C "${PWD}-wt/<id>" rebase main && git merge --ff-only factory/<id>
  ```
- **Questions** only the user can answer, each with your proposed answer.
- **Escalations:** what failed, why you think it failed, and what you suggest.
- **Next:** the next batch, and what it waits for.

## 7. After the user merges

When the user says the branches are merged:

1. If more than one branch was merged, check `main` as a whole (each branch was verified alone):
   ```bash
   wt="${PWD}-wt/main-check"; rd="$FACTORY_HOME/runs/main-check-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$rd"
   git worktree add -q --detach "$wt" main
   "$FACTORY_HOME/bin/sandbox" --net none "$wt" "$rd" -- scripts/verify > "$rd/verify.log" 2>&1; echo "verify exit $?"
   git worktree remove --force "$wt"
   ```
   If it fails, stop and show the user `verify.log`; don't start a batch on a red `main`.
2. Clean up each merged task: if its worktree holds nothing but `REPORT.md` (a copy is in the run
   dir), `git worktree remove --force` it, then `git branch -d factory/<id>`. `-d` refuses an
   unmerged branch; if it does, tell the user instead of forcing it.
3. Go back to step 2 until every task is merged. Then tell the user the spec is done.
