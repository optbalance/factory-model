# Operating the factory

Which command to use for each job. The machine must meet `docs/factory/factory-contract.md` first.
Run the commands from `~/factory-model`; paths assume products are in `~/projects/<product>`. How the
pieces fit together is in `docs/how-to/how-the-factory-works.md`.

## Commands at a glance

| Job | Command | Status |
|---|---|---|
| Start the orchestrator | `bin/start <harness>` | ✓ |
| Check the factory layout | `bin/check-factory` | ✓ |
| Test the guards | `guards/test.sh` | ✓ |
| Build or rebuild a product's worker image | `bin/build-worker <product-dir> [harness...]` | ✓ |
| Run one command in a sandbox (debugging) | `bin/sandbox [--net none] <worktree> <rundir> -- <command>` | ✓ |
| Check a product against the contract | `bin/check-product [--run] <product-dir>` | not built yet (Module 1) |
| Run one role on any harness | `bin/agent-run` | not built yet (Module 3) |
| Implement one task, gated by verify | `bin/run-task` | not built yet (Module 3) |
| Run a batch of tasks in parallel | `bin/fan-out` | not built yet (Module 6) |
| Collect a run's results | `bin/collect` | not built yet (Module 6) |
| Measure the factory | `bin/eval` | not built yet (Module 8) |

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

1. The planner lists it in `docs/specs/NNN-name/dependencies.md`.
2. You approve it and commit the change (build files, lockfiles) on the product's `main`.
3. Rebuild the worker image (step 3), then run the tasks.

## 5. After a task is merged

```bash
git -C ~/projects/<product> worktree remove ~/projects/<product>-wt/<id>
git -C ~/projects/<product> branch -d factory/<id>
```

Run logs stay in `runs/` (gitignored); delete old ones when you no longer need them.

## 6. Maintain the factory

| When | Command |
|---|---|
| After pulling factory changes | `bin/check-factory`, then `guards/test.sh` |
| After changing a guard | `guards/test.sh`, with a new allow case and block case |
| After changing a `Containerfile` | `bin/build-worker` for each product |
| A token expires (Claude Code: yearly) | generate a new one, replace it in `~/.config/factory/env`, restart through `bin/start` |
