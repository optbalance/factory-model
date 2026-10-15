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
  rounds. Add the step only if Module 8 evals show that, and after trying more concrete task files
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
- **Fix rounds and escalation in `bin/run-task` have never run.** Module 3's second "Try it"
  (`docs/how-to/building-the-factory.md`) was skipped: no run so far failed verify, so the fix
  loop (`fix.md`, `CONTINUE=1` on the implementer's session, then a fresh `implementer-strong`
  session) is untested. What could go wrong: `--continue` doesn't find the session under
  `$rundir/claude/implementer`, the fix prompt lacks what the model needs, or escalation never
  triggers, and a task that could be fixed ends `red`. Test it when the first real task goes red,
  or with a task the existing tests contradict; expect `calls.log` to show three `implementer`
  calls and one `implementer-strong`. Note that an implementer that correctly refuses and changes
  nothing still ends `green` until the Module 5 reviewer exists.
