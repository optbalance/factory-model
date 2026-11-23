# Operating the factory

Which command to use for each job. The machine must meet `docs/factory/factory-contract.md` first.
Run the commands from `~/factory-model`; paths assume products are in `~/projects/<product>`. How the
pieces fit together is in `docs/how-to/how-the-factory-works.md`.

## Commands at a glance

| Job | Command | Status |
|---|---|---|
| Start the orchestrator | `bin/start <harness>` | ✓ |
| Specify and plan work | skills `spec`, then `plan`, in a session started with `bin/start` in the product repo; with a tracker they write to the board | ✓ |
| Check the factory layout | `bin/check-factory` | ✓ |
| Test the guards | `guards/test.sh` | ✓ |
| Build or rebuild a product's worker image | `bin/build-worker <product-dir> [harness...]` | ✓ |
| Run one command in a sandbox (debugging) | `bin/sandbox [--net none] <worktree> <rundir> -- <command>` | ✓ |
| Check a product against the contract | `bin/check-product [--run] <product-dir>` | not built yet (Module 1) |
| Run one role on any harness | `bin/agent-run <role> <workdir> <prompt-file> <run-dir>` | ✓ |
| Implement one task, gated by verify | `bin/run-task <worktree> <task-file> <run-dir>` | ✓ |
| Run a batch of tasks in parallel | `bin/fan-out <product-dir> <task-file>...` | ✓ |
| Collect a run's results | `bin/collect [run-dir \| task-run-dir]` | ✓ |
| Review a task, approve or send remarks (local forge) | `bin/start bin/review [product-dir]` | ✓ |
| See where every task's review stands | `bin/review status [product-dir] [all \| <id>]` | ✓ |
| Act on the forge's decisions: rework, clean up merged tasks | `bin/start bin/review sync [product-dir]` | ✓ (GitHub forge untested on GitHub) |
| Send remarks back to the implementers | `bin/start bin/rework <task-run-dir>...` (`bin/review` calls it) | ✓ |
| One forge operation (debugging) | `bin/forge <name\|remote> <product-dir>`, `bin/forge <submit\|status\|remarks\|merge> <product-dir> <task-run-dir>` | ✓ |
| Run a spec's tasks to merge-ready branches | skill `orchestrate`, in a session started with `bin/start` in the product repo (without a tracker) | ✓ |
| Work from the board: plan, run, move cards (section 7) | `bin/start bin/tracker sync <product-dir>`, from a timer or by hand | ✓ (Linear) |
| Plan one story now, headless (debugging) | `bin/start bin/tracker plan <product-dir> <story>` | ✓ |
| Write a directory of task files to a story | `bin/tracker publish <product-dir> <story> <dir>` | ✓ |
| One tracker operation (debugging) | `bin/tracker name <product-dir>`, `bin/tracker <items\|read\|write\|move\|comment\|comments> <product-dir> [args...]` | ✓ |
| Turn failures into factory fixes | skill `retro`, in a session started with `bin/start` in `~/factory-model` | ✓ |
| Measure runs: cost, turns, fix rounds | `bin/metrics [--tsv] [dir...]` | ✓ |
| Measure the factory with evals | `bin/eval` | postponed (Module 9) |

Commands marked "not built yet" are specified in `docs/how-to/building-the-factory.md`, in the module
shown. Update this table as each one lands.

---

## 1. Start the factory

```bash
cd ~/factory-model
bin/start claude          # or any harness, or a factory script: bin/start bin/fan-out ...
```

`bin/start` loads the secrets from `~/.config/factory/env` and starts the command with them.
Everything the orchestrator runs inherits them, and `bin/sandbox` passes on the names listed in
`config/sandbox-env`. If `bin/sandbox` prints `<NAME> (config/sandbox-env) is not set`, the
orchestrator wasn't started through `bin/start`, or the file lacks that line.

Choose the sandbox backend with `SANDBOX` before starting (default `docker`):

```bash
SANDBOX=podman bin/start claude
```

## 2. Plug in a product (once per product)

1. Make the product meet `docs/product/product-contract.md`, committed on its `main`.
2. Build its worker image:
   ```bash
   bin/build-worker ~/projects/<product>              # harnesses from config/routing.json
   bin/build-worker ~/projects/<product> claude       # or name them
   ```
   The image is `factory-worker-<product>`, built from what's committed on `main`. Use the same
   `SANDBOX` value you run with: Docker and Podman keep separate image stores.
3. Check that verify passes in the sandbox, offline:
   ```bash
   wt=~/projects/<product>-wt/check; rd=~/factory-model/runs/check; mkdir -p "$rd"
   git -C ~/projects/<product> worktree add -q --detach "$wt" main
   bin/sandbox --net none "$wt" "$rd" -- scripts/verify && echo "verify passes"
   git -C ~/projects/<product> worktree remove "$wt"
   ```
   `bin/check-product --run` will do this once it's built.

## 3. Rebuild the worker image

Run `bin/build-worker` again whenever the product's `main` changes its toolchain or dependencies,
or the factory changes `sandbox/Containerfile`, an adapter's `Containerfile` or the harnesses in
`config/routing.json`. Changes to guards, roles, skills or routing models need no rebuild: the
factory is mounted into the sandbox read-only at run time.

## 4. Change dependencies

Tasks never change dependencies. When a spec needs one:

1. The planner lists it in `docs/specs/NNN-name/dependencies.md`. With a tracker, the headless
   planner asks for it in its questions instead, and the story goes to `blocked`.
2. You approve it and commit the change (build files, lockfiles) on the product's `main`.
3. Rebuild the worker image (step 3), then run the tasks. With a tracker, move the story back to
   `todo`: it is planned again on the new `main`.

## 5. Run a batch of tasks

Without a tracker; with one, `bin/tracker sync` does this (section 7). Pick tasks whose `touches` don't overlap and that don't depend on each other (or whose
`depends_on` are merged). Their task files must be committed on the product's `main`.

```bash
bin/start bin/fan-out ~/projects/<product> docs/specs/NNN-name/tasks/<id>.md ...
bin/collect                  # the newest run; or bin/collect runs/<timestamp>
```

`fan-out` creates `~/projects/<product>-wt/<id>` on branch `factory/<id>` for each task, runs
them in parallel and writes to `runs/<timestamp>/<id>/`. A task that passes verify and the AI
review is submitted to the product's forge (`factory.properties`, product contract Step 6): on
GitHub it gets a pull request. `collect` shows per task what to do next: review a green,
approved one; read `review-<n>.md` when the reviewer still has findings; read `verify.log` and
`REPORT.md` for a red one. To re-run a task, remove its worktree and branch first (the
orchestrate skill does this when it re-queues one).

## 6. Review and merge

Locally (`forge=local`, the default), from the product repo or with its path:

```bash
bin/start bin/review ~/projects/<product>
```

Pick a task: it shows the `collect` summary and the AI review, then the diff. Then:

- **approve:** rebases the branch onto `main` and adds it to `main` as one commit,
  `factory: <id>` (like a squash merge on a forge), verifies `main` in an offline sandbox and
  removes the worktree and branch. The product checkout must be clean and on
  `main`.
- **remarks:** opens `$EDITOR`; what you write goes to the implementer, which reworks the same
  branch in its own session, then verify and the AI review run again. It runs in the background;
  the task comes back to the list when it's green, even if the AI reviewer objects to your
  remarks; its review is shown, and you decide.
- **re-queue:** the task file or the spec was wrong; the orchestrate skill rewrites it and runs
  the task again.

On GitHub (`forge=github`), review the pull request: merge it, or send remarks as a review
("Review changes" → "Comment"; the review's text and line comments are the remarks), or close it
to re-queue. The pull request is opened as you, and GitHub doesn't let you approve or request
changes on your own, so "Comment" is how you send remarks. A colleague sends them with "Request
changes"; their "Comment", approvals and conversation comments are discussion and start nothing.
An approval doesn't merge or clean up anything: merging does. Then:

```bash
bin/start bin/review sync ~/projects/<product>      # reworks, and cleans up merged tasks
bin/review status ~/projects/<product>              # one line per task, with its pull request
```

For a closed pull request, `sync` removes the task's branch from the remote (only if nobody
else pushed to it), so the task can be re-queued under the same id. `sync` acts only on this
machine's tasks (a `factory/<id>` branch with a run dir here), never on
other people's branches or pull requests on the same remote. Run it after you review; the
orchestrate skill also runs it. `bin/start` is needed when a rework may start: the agents need
the secrets.

Run logs stay in `runs/` (gitignored); delete old ones when you no longer need them.

## 7. Work from the board (with a tracker)

Once per product: name the tracker in `factory.properties` and set up the board's statuses
(product contract, Step 6), sign the host in to the tracker (factory contract, Step 9), and add
the product's timer line (factory contract, Step 10). From then on you work on the board; the
timer runs `bin/tracker sync` every few minutes, and each pass acts on what changed:

| You | The factory, on the next pass |
|---|---|
| Write a story (status `open`), or have the `spec` skill write it | nothing: `open` is yours |
| Move the story to `todo` | plans it headless: tasks on the story and `refined`, or questions as a comment and `blocked` |
| Answer in comments (on the story or its tasks), move it back to `todo` | plans it again with your comments; a task that stays keeps its id and is updated, a dropped one is `canceled` |
| Move the story to `in-progress` | runs its tasks, at most 3 at a time, by `depends_on` and `touches`; each goes `in-progress`, then `in-review` with the pull request's link, or `blocked` with the reason |
| Review the pull request: merge, request changes, or close | `done`; a rework (`in-progress`, then `in-review` again); or `blocked` |
| Edit a `blocked` task or comment on it, move it to `todo` | runs it again from `main`, with your comments; the earlier attempt is kept as `abandoned.patch` |
| Move a task to `canceled` | leaves it; the story is `done` when every task is `done` or `canceled` |

Rules of the board:

- **Code remarks go in the pull request**, not in tracker comments (section 6).
- **Moving a card to `done` does nothing.** A task is done when its commit is on `main`.
- **An edit to a running task doesn't reach it.** It runs from the copy taken when it started;
  edit it once it's `blocked`.
- **Every comment the factory posts starts with `🏭 factory`.** Never start one of yours that way:
  the factory skips such comments.
- **After a reboot, do nothing.** A plan, batch or rework the reboot killed runs again on the
  next pass, without a card moving.

Where to look when something seems stuck:

- the timer's log, `runs/sync-<product>.log`: a dated line for each thing a pass did;
- a plan: `runs/plan-<story>/<n>/` (`brief.md` is what the planner was given, `planner.log`,
  `plan/` the task files or `QUESTIONS.md`);
- a task: `bin/review status ~/projects/<product>`, and `bin/collect` on its run dir;
- run a pass by hand: `bin/start bin/tracker sync ~/projects/<product>`. A second pass while one
  runs exits at once; so does `bin/review sync` while another runs.

To pause a product, comment out its timer line. Runs already started finish; nothing new starts.

## 8. Maintain the factory

| When | Command |
|---|---|
| After pulling factory changes | `bin/check-factory`, then `guards/test.sh` |
| After changing a guard | `guards/test.sh`, with a new allow case and block case |
| After changing a `Containerfile` | `bin/build-worker` for each product |
| A token expires (Claude Code: yearly) | generate a new one, replace it in `~/.config/factory/env`, restart through `bin/start` (a timer picks it up on its next pass) |
