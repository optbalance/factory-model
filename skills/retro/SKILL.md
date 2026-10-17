---
name: retro
description: Read the factory log, recent runs and reports, find what made tasks fail or need help, and propose concrete fixes in the right layer of the factory or product. Use in the factory repo after a batch or a spec is done. Changes nothing without the user's approval.
---

# Retro: turn failures into factory improvements

Every failure should make the factory better, in the layer where the cause is. You read the
evidence, find the causes, and propose concrete changes. The user approves each one. Work in the
factory repository's root (`$FACTORY_HOME`). Read its `AGENTS.md` first: its rules decide where
a fix may go.

## 1. Gather the evidence

- `docs/factory-log.md`: only the open lines, `grep -n 'fix: pending' docs/factory-log.md`. Don't
  read the whole log; the fixed lines are history, searched in step 2.
- `runs/`: the runs since the last retro (or the ones the user names). For each task: `status`,
  `verdict`, `calls.log`, `review-<n>.md`, `REPORT.md`, the end of `verify.log`, and
  `abandoned.patch` if the task was re-queued. Open `*.events.jsonl` only to answer a specific
  question (which file the agent read, which command failed).
- The task files and specs of those runs, in the product repo (a task's run dir is named after
  its id; `worktree` in it shows the product's path).
- `docs/todo.md`: issues already known and postponed.
- `bin/metrics runs/<run> ...` over the same runs: per task, its fix rounds, escalation,
  review rounds that asked for changes, turns, time and cost, with the most turns first.

Also look for failures nobody logged: approved branches whose reviews name real gaps, fix rounds
in `calls.log` (more than one `implementer` call), escalations (`implementer-strong`), and the
same open question in several reports. Add a log line for each.

Use the metrics to find outliers among tasks that went well too: many more turns, fix rounds or
cost than the others. Read their task files and look for what they share: a part of the code, a
kind of work (concurrency, parsing, migrations), a missing piece of context. Shared traits are a
pattern, such as "tasks touching concurrency take twice the turns: the task files don't say which
locking pattern to follow". With few tasks, a pattern is a guess: give the numbers, and propose a
fix only when it's cheap or the pattern repeats.

## 2. Find the causes

Group failures by cause, not by task. For each group, find the root cause: the first thing that,
if it had been different, would have prevented the failure. "The model made a mistake" isn't a
cause; ask what it lacked or what allowed the mistake through. A cause that shows up once may be
noise; say how many times you saw it.

For each cause, grep the log for earlier lines with the same cause or failure
(`grep -n -i '<keyword>' docs/factory-log.md`). A match whose `fix:` names a change means that
fix didn't hold: say so, and propose a stronger fix or a different layer instead of repeating it.

Then pick the layer the fix goes into:

| Failure type | Fix goes into |
|---|---|
| Agent didn't know something about the product | product `AGENTS.md` |
| Agent did a procedure wrong or inconsistently | a skill or role prompt |
| Agent did something that must *never* happen | a guard (plus a case in `guards/test.sh`) |
| Bad code passed | a test, `scripts/verify`, or the reviewer role |
| Task was badly scoped | the `plan` skill rules / task template |
| One model keeps failing one kind of task | `config/routing.json` |
| A harness ignored a guard, flag or config | that harness's adapter (`adapters/<name>/`) |

Product knowledge never goes into the factory repo, and harness specifics only into
`adapters/`. If a fix would break that, it belongs in the product, or it needs the user's
decision.

## 3. Propose

Show the user one proposal per cause, most impactful first:

- **Evidence:** the log lines and run dirs, and how often it happened.
- **Cause** and **layer.**
- **Change:** the exact file and the edit, short enough to read in place. Prefer the smallest
  change: one rule sharpened beats a new section; a new script needs strong evidence.
- **Cost:** what it adds (prompt length, a verify step, a stronger model's price).

Don't propose what `docs/todo.md` already lists unless the evidence changes its priority; then
say so. If a cause can't be fixed yet, propose a `docs/todo.md` bullet instead.

## 4. Apply what the user approves

- Make each approved change. In the factory repo, run `bin/check-factory`, and `guards/test.sh`
  after a guard change.
- Changes to the product's `AGENTS.md`, `scripts/verify` or tests go into the product repo; make
  them only if the user asks, as their own commit on its `main`.
- Update each log line's `fix:` with what changed (file, and the change in a few words), or
  `none: <why>` for what the user rejected.
- Commit the factory changes and the log together. Don't push.

End with a short summary: what changed, what was rejected, and what to watch for in the next
runs to see whether each fix worked.
