# To do

Known issues and missing features that are worth solving but not urgent. One bullet each: what's
wrong, where (files), what goes wrong because of it, and a possible fix if known. Remove a bullet
when it's fixed.

- **Product identity is the repo directory's basename, so worker images can collide.** `bin/sandbox`
  and `bin/build-worker` derive `<product>` from the basename of the product repo directory
  (`~/projects/<product>`), not from its full path. Two products whose repos share a basename
  (`~/projects/shop`, `~/work/shop`) both use the image `factory-worker-shop`, so building one
  overwrites the other's, and tasks of one product run in the other's toolchain. Possible fix:
  derive the name in one helper used by both scripts, from the basename plus a short hash of the
  absolute repo path.
- **`bin/build-worker` never reuses its cache above the toolchain layer.** Each layer is a separate
  `docker build` whose `FROM` is the previous layer's tag. A fully cached build still produces a
  new image ID (two consecutive cached builds of `sandbox/Containerfile` on the same base gave
  different IDs), so the next layer's `FROM` resolves to a new digest, misses its cache and
  rebuilds. Measured on a Gradle product with docker 29.9.3 and BuildKit v0.34.2: toolchain 1s
  (cached), base 33s, pi 28s, claude 11s, about 70s per run with nothing changed. `bin/fan-out`
  pays it on every batch, and a per-task image rebuild before verify would pay it on every verify
  round. Cause not confirmed; likely suspect is BuildKit provenance metadata making image IDs
  differ. Possible fix: check whether `--provenance=false` gives stable IDs; otherwise build all
  layers in one BuildKit graph (one multi-stage build or `docker buildx bake`), so layers chain
  by cache key instead of by tag.
- **No hard stop for dependencies installed into the worktree.** Tasks must not change
  dependencies; `bin/run-task` (`docs/how-to/building-the-factory.md`, Module 3) enforces that only
  through offline `scripts/verify`, which fails when a build tool that downloads outside the
  worktree (Gradle, Maven, Cargo, Go) meets a dependency the image lacks. Package managers that
  install into the worktree (npm `node_modules/`, pip into a venv) pass that check: an agent with
  network during its run can install a package, and verify still passes. A change to
  `package.json` or a lockfile shows in the reviewer's diff, but an install that isn't saved there
  slips through until a fresh worktree fails. No current product is affected. Revisit when the
  first such product is plugged in. Possible fix: a product-provided command that lists declared
  dependencies, compared by `run-task` before and after the task (removed once as unneeded
  machinery; it read build files the agent can edit, so it must use `main`'s copy).
- **`SANDBOX=bwrap` fails on hosts that restrict unprivileged user namespaces.** On Ubuntu 23.10+
  (`kernel.apparmor_restrict_unprivileged_userns = 1`), every `bin/sandbox` call in bwrap mode
  aborts before running the command: `bwrap: setting up uid map: Permission denied` (default
  network), or `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted` (`--net none`). So
  the bwrap fallback is unusable, and the "Try the sandbox" `--net none` check in
  `docs/how-to/building-the-factory.md` (Module 2) fails for the wrong reason and proves nothing.
  Possible fix: document the host setup in Module 2, an AppArmor profile for `/usr/bin/bwrap`
  that grants `userns` (as Ubuntu ships for other tools in `/etc/apparmor.d/`), and have
  `bin/sandbox` fail with a clear message pointing to it.
- **No headless planner step in `bin/run-task`, on purpose.** Planning happens once, interactively,
  with the `plan` skill; the reviewed task file is the implementer's whole instruction, so there is
  no `roles/planner.md` and nothing calls `agent-run planner` (the `planner` entry in
  `config/routing.json` only records the model for interactive planning sessions). What could go
  wrong: a cheap implementer may fail on approach (design) even with a good task file, burning fix
  rounds. Add the step only if Module 9 evals show that, and after trying more concrete task files
  first. Possible fix: `run-task` calls `agent-run planner` (read-only tools) before the
  implementer, the planner writes `$rundir/approach.md`, and `run-task` appends it to `brief.md`;
  then write `roles/planner.md`. Cost: one strong-model call per task.
- **Module 3's "Done when" provider switch is untested.** Only one provider and harness (Claude
  Code) is set up, so the check in `docs/how-to/building-the-factory.md` (Module 3, "Done when"):
  switch the implementer to another provider by editing only `config/routing.json`, and the same
  task still goes green, was replaced by a model switch within Claude (`sonnet` → `opus`). That
  proves model routing, not that `bin/agent-run`, `bin/run-task` and the run artifacts they read
  are free of Claude-specific assumptions. What could go wrong: the second adapter breaks the
  runner, or needs changes outside `adapters/`. Fix: when a second provider or harness is
  available, write its adapter (`docs/adapter/adapter-contract.md`), switch only the implementer's
  routing entry, and rerun a small task to green; then do the same for the harness.
- **Verify fix rounds and escalation in `bin/run-task` have never run.** Module 3's second "Try
  it" (`docs/how-to/building-the-factory.md`) was skipped: no run so far failed verify, so the
  verify fix loop (`fix.md`, then a fresh `implementer-strong` session) is untested. Continuing the
  implementer's session does work: in shovel task 005 the AI review's fix round
  (`review-fix.md`, Module 5) and a rework two days later ran in the first run's session (one
  `session_id` in `implementer.events.jsonl`). What could still go wrong: the verify fix prompt
  lacks what the model needs, or escalation never triggers, and a task that could be fixed ends
  `red`. Test it when the first real task goes red,
  or with a task the existing tests contradict; expect `calls.log` to show three `implementer`
  calls and one `implementer-strong`. A run that changes nothing ends `green` with
  verdict `changes-needed` (the reviewer sees an empty diff). The same run tests `adapters/claude/metrics.sh` on a
  continued session (`docs/how-to/building-the-factory.md`, Module 8, Claude step 2): whether
  `num_turns` and `duration_ms` accumulate like cost does.
- **The reviewer is the same model family as the implementer.** Module 5's design
  (`docs/how-to/building-the-factory.md`) wants a second family to check every green branch, but
  only Claude Code is set up, so `config/routing.json` routes `reviewer` to Opus reviewing Sonnet's
  work. Models of one family share blind spots, so the reviewer misses more of the implementer's
  mistakes, and Module 5's "Try it" (3 tasks reviewed by the same family, 3 by a different one,
  compare the findings) can only be half done. Fix: when a second harness or provider is
  available (see the provider-switch bullet above), route `reviewer` to it, rerun the comparison
  and keep the family that finds more real issues.
- **The GitHub forge has never run against GitHub.** `forges/github/` (Module 10,
  `docs/forge/forge-contract.md`) was tested only with a stub `gh` and a local bare repo as the
  remote; `gh` isn't installed on the host yet. The `gh` commands follow its manual and GitHub's
  REST docs, but these are unverified: that the review list's `state` is `COMMENTED` for a
  "Comment" review and `CHANGES_REQUESTED` for "Request changes", that GitHub also refuses
  "Request changes" on your own pull request (its docs say so only for approving), that
  `GH_REPO` with a host part works for `gh api`'s `{owner}/{repo}`, and how `gh pr create`
  behaves when a closed pull request already exists for the branch. What goes wrong if one is
  off: `bin/review sync` never sees your remarks, or `submit` fails after the push. Test it with
  a throwaway GitHub repository, or with a real task: install `gh`, `gh auth login`, add
  `factory.properties` with `forge=github`, then follow Module 10's "Try it", including a squash
  merge and running `bin/review sync` twice.
- **`run-task --rework`'s handling of your remarks against the AI reviewer is untested with real
  agents.** One real rework ran (shovel task 005, before the fix): the implementer applied the
  remark and wrote `Review answers`, then the reviewer, who didn't see the remarks, had it
  reverted. Since then the reviewer gets the remarks, and remarks decide *what*, the reviewer
  *how* (`bin/run-task` `user_reviews`, `roles/reviewer.md`), tested with a stubbed
  `bin/agent-run` only. Check on the next real remark: the reviewer no longer flags the remark as
  scope, bugs in the remark's code are still fixed, and a genuine conflict ends as
  `[AI reviewer objects]` with the conflict under `Review answers`.
- **Unclear remarks make the implementer guess.** A remark that slips through incomplete or
  vague, as your own "Comment" or a colleague's "Request changes" ("Main:71 Why is it here?",
  "if while {…figure out something better…}"), goes to the implementer as is. The rework prompt
  (`bin/run-task`, `rework-<n>.md`: "Fix each one…") pushes it to act, so it invents a change
  you didn't ask for (removes the code you only asked about, rewrites beyond the spot). The
  reviewer role (`roles/reviewer.md`) makes it worse: a remark not carried out is a finding, so
  holding back gets pushed into guessing. And a question back to you is hidden locally:
  `bin/collect` (shown by `bin/review`) prints only "Not done" and "Open questions", not
  "Review answers"; on GitHub the PR comment shows it, titled "Addressed your review" even when
  nothing changed (`forges/github/submit.sh`). Possible fix, prompt-level only (no remark
  pre-check step or agent): (1) the rework prompt acts on a remark only when the implementer can
  say in one sentence what you want and the change stays where the remark points: a clear
  change is made; a question is answered under "Review answers" with no code change (a defect
  it reveals is proposed, not fixed); an open-ended remark at a spot gets one concrete change
  there, with why; an unclear, cut-off or contradictory one gets no change, a quote and a
  question, with options. (2) The reviewer role: a remark answered as a question, or asked
  about as unclear, isn't a finding, unless it was clear, or a question got an unasked-for code
  change. (3) `bin/collect` prints "Review answers" when the run dir has `user-review-*.md`; the
  PR comment says "Answered your review in <sha>". Test with real agents: send one vague remark
  next to a real one.
- **Prompt text lives inside `bin/run-task`.** The messages the runner sends to agents are
  `printf` strings in the script: the task brief (lines ~17-18), the verify fix prompt (~38),
  the reviewer's brief and its round and `User review:` lines (~56-58), the rework prompt (~75),
  the review fix prompt and the user-remarks rule (~88-90). Role prompts already live in
  `roles/*.md`; these don't. What goes wrong: prompts are the part of the factory tuned most
  often (the last three fixes were wording), yet each change edits bash with `'"'"'` quoting, a
  prompt can't be read or diffed as a whole, and retro or a later eval (Module 9) can't point at
  "the rework prompt" as one file. Possible fix: a `prompts/` directory next to `roles/`, one file
  per message, named by when it's sent: `implement.md`, `verify-fix.md`, `review.md`,
  `review-round.md`, `review-user.md`, `review-fix.md`, `review-fix-user.md`, `rework.md`.
  Conditional parts become their own files that the script appends, so the files hold no logic.
  Placeholders like `{task}`, `{round}`, `{user_reviews}` are filled with bash's
  `${text//\{task\}/$task}`, not `sed` or `envsubst` (`envsubst` isn't a host tool in the
  factory contract, and `sed` breaks on `/` and `&` in values). Dynamic content (verify output,
  the reviewer's findings, your remarks) is appended after the file, as now. `bin/run-task`
  keeps only the plumbing; `bin/check-factory` checks the files exist; Module 3 and 5's code
  listings in `docs/how-to/building-the-factory.md` and the course text that quotes prompts are
  updated. Out of scope: guard block messages (`guards/`, tied to their checks) and texts for
  you, not agents (PR body and comment, `bin/collect`).
- **Cleanup of a task's worktree and branch is done in several places, and not at all after a
  false start.** `bin/cleanup <product-dir> <id>` (added 2026-10-28) is the one way to free a
  task id: it saves any work on the branch or in the worktree (besides `REPORT.md`) as
  `abandoned.patch` in the task's newest run dir, then removes `<product>-wt/<id>` and
  `factory/<id>`; it refuses when there is work and no run dir. So far only the orchestrate skill's
  re-queue step uses it. Every other place that frees a task must call it instead of its own git
  commands, so the rules (what's kept, where, when to refuse) live in one script:
  - **False start.** When the implementer's harness call fails before doing any work (shovel 004,
    005 on 2026-10-23 and 007 on 2026-10-28: authentication failed at turn 1), `bin/run-task`
    ignores the failure (`run ... || true` in `call()`), `scripts/verify` passes on the unchanged
    `main`, and the run ends `green` with review `error`; the branch and worktree stay, and
    `bin/fan-out` refuses the task until someone removes them. Fix: `adapters/claude/run.sh` exits
    non-zero when the result has `is_error: true` (add it to `docs/adapter/adapter-contract.md`);
    `bin/run-task` ends with status `not-started` when the first implementer call fails and the
    worktree is unchanged, skipping verify and review; `bin/fan-out`, which created the worktree
    and branch, calls `bin/cleanup` for that status; `bin/collect` shows `not-started` with the end
    of the implementer's events log; the orchestrate skill re-queues it without asking.
  - **After review (merged).** `bin/review`'s own `cleanup()` (worktree remove, then `branch -d`
    or `-D`; leaves the worktree when it has changes besides `REPORT.md`) becomes a call to
    `bin/cleanup`. Its "left in place" case is then `bin/cleanup` saving the changes to
    `abandoned.patch` instead; decide whether a merged task's leftover changes should still stop
    and go to the user.
  - **Discard (closed / re-queued in review).** `docs/forge/forge-contract.md`'s `discard.sh`
    removes only what the forge published; the local branch and worktree are left "for the
    orchestrate skill". `bin/review sync` calls `bin/cleanup` after a successful `discard.sh`, so
    a closed task is freed in one step, with its work kept in the run dir.
  - **Any new path that frees a task** (a cancelled batch, an abandoned rework) uses `bin/cleanup`.
  Also: the run-dir lookup (newest `runs/*/<id>/worktree` naming the worktree) is now in both
  `bin/cleanup` and `bin/review`'s `tasks()`; move it into one helper when wiring `bin/review`.
- **`bin/fan-out` starts a batch without the harness credentials.** Since 2026-10-28 `bin/sandbox`
  reads any `config/sandbox-env` name missing from the environment from `$FACTORY_ENV`
  (`bin/lib/env.sh`), because Claude Code doesn't pass `CLAUDE_CODE_OAUTH_TOKEN` to its Bash tool's
  shells (that caused the 004, 005 and 007 false starts). A name missing from both still only
  warns, and the batch runs into a false start. Possible fix: `bin/fan-out` checks the required
  names (a way to mark which are required in `config/sandbox-env`) before creating any worktree
  and refuses to start (exit 2).
- **`bin/` has outgrown separate bash scripts.** About 980 lines across 15 `bin/` scripts, the
  forge scripts and the adapters (2026-10-28), and the same parts are repeated instead of shared:
  - the `FACTORY_HOME` preamble in 11 scripts;
  - finding the product's main checkout (`rev-parse --git-common-dir`) in `cleanup`, `review`,
    `rework` and `sandbox`;
  - the task's worktree path `<product>-wt/<id>` in `cleanup`, `fan-out` and `review`;
  - the newest run dir of a task in `cleanup` and `review`;
  - routing lookups through `jq` in `agent-run`, `build-worker`, `metrics` and the GitHub forge;
  - the product name in `sandbox` and `build-worker` (see the image-collision bullet above).

  What goes wrong: a rule changes in one copy and not the others (the cleanup bullet above is one
  case), every new script copies the boilerplate again, and nothing is unit-tested, because bash
  tests only run end to end. Fix: join the scripts into one CLI application (`factory <command>`:
  `fan-out`, `collect`, `review`, `cleanup`, `sandbox`, ...) written in a platform-independent
  language, with a typed model of product, task, run and worktree in one place, unit tests, and
  the forge and adapter contracts as interfaces. Things to decide first:
  - the language: a single static binary (Go) adds nothing the host must install, while Python
    needs an interpreter on every host;
  - what stays a script: anything that runs inside the worker image (`adapters/*/run.sh`, the
    hooks in `guards/`) either stays bash or needs the CLI in the image;
  - the forge and adapter contracts (`docs/forge/forge-contract.md`,
    `docs/adapter/adapter-contract.md`) are defined as scripts per forge or harness, so decide
    whether they stay as external scripts the CLI calls (keeping them pluggable) or become modules;
  - `docs/how-to/building-the-factory.md` teaches each module through these bash listings and has
    to be rewritten with them;
  - "platform-independent" stops at the sandbox: docker, podman or bwrap and git worktrees still
    mean Linux or macOS.

  A cheaper step that can happen first, and that the rewrite reuses: move the repeated parts into
  `bin/lib/` (started with `bin/lib/env.sh`), one helper per concept (product, task paths, run
  dirs, routing).
