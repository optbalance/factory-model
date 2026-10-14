# Adapter contract

What an adapter must provide so the factory can run a harness. One adapter per harness, in
`adapters/<harness>/`. Everything specific to that harness (CLI flags, config and hook formats,
install steps, auth variables, session handling) lives there and nowhere else; the rest of the
factory calls it through one neutral interface. Work through the steps in order. Worked examples
for Pi, Claude Code, Codex and Antigravity are in `docs/how-to/building-the-factory.md` (the
"Harness-specific steps" of Modules 0, 2 and 3). What the machine must provide is in
`docs/factory/factory-contract.md`; what a product must provide is in
`docs/product/product-contract.md`.

| Step | What | Adapter file |
|---|---|---|
| 1 | Image layer | `adapters/<harness>/Containerfile` |
| 2 | Authentication | names in `config/sandbox-env` |
| 3 | Guard wiring | hook, extension or plugin under `adapters/<harness>/` |
| 4 | Skills | the same, pointing at `skills/` |
| 5 | The runner: `run.sh` | `adapters/<harness>/run.sh` |
| 6 | Routing keys | entries in `config/routing.json` |
| 7 | Check | — |

The adapter is only a translator. It never decides policy: what is blocked comes from `guards/`,
what each role does from `roles/` and `config/routing.json`, what the product is from its
`AGENTS.md`. If an adapter needs a rule of its own, the rule belongs in one of those places.

---

## Step 1. Image layer: `Containerfile`

**What:** a layer of the worker image that installs the harness, with this shape:

```dockerfile
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
# install the harness here, at an exact pinned version
```

It must:

- pin the exact harness version, so every product's image runs the same harness;
- turn off self-updating (the image is rebuilt instead);
- not change the product's toolchain: a runtime the harness needs (for example Node) stays off
  the `PATH`, or is copied in as a single binary;
- use fully qualified image names (`docker.io/library/...`), because Podman refuses short ones.

**Why:** `bin/build-worker` stacks it on the factory base layer (`sandbox/Containerfile`), which
sits on the product's toolchain image. It installs the layers of the harnesses named in
`config/routing.json`.

## Step 2. Authentication

**What:** the harness authenticates only with environment variables, and their **names** are
listed in `config/sandbox-env`. Values never appear in the repo; they come from
`~/.config/factory/env` through `bin/start` (`docs/factory/factory-contract.md`, Steps 5–6).
Document the variable in that contract's table.

**Why:** the sandbox passes only listed names. The worker never sees your host sign-in, your
host config directory or any other credential.

## Step 3. Guard wiring

**What:** translate the harness's "about to run a tool" event into calls to the neutral guards:

| Tool kind | Guard | Argument |
|---|---|---|
| runs a shell command | `$FACTORY_HOME/guards/bash.sh` | the command |
| writes or edits a file | `$FACTORY_HOME/guards/files.sh` | the file path |

Exit `0` allows the call. Exit `2` blocks it, and the guard's stderr is the reason, written for
the model: pass it back to the model unchanged. Cover **every** tool of each kind the harness
has, including ones a role doesn't use today. If the guard can't be run (missing
`FACTORY_HOME`, a crash), block.

**Why:** the guards are the factory's rules for agents (no push, no secrets files, no
`curl | sh` and so on). They're written and tested once (`guards/test.sh`); the adapter only
calls them. A harness without a pre-tool hook can't meet this step.

## Step 4. Skills

**What:** the harness loads the factory's skills from `$FACTORY_HOME/skills/` (Agent Skills
format), explicitly on every run, and no other skills.

**Why:** every run gets the same skills, whatever is installed on the machine or in the product.

## Step 5. The runner: `run.sh`

**What:** an executable `adapters/<harness>/run.sh`. `bin/agent-run` calls it inside the sandbox
with five arguments:

```
run.sh <cfg> <role> <workdir> <prompt> <rundir>
```

| Argument | What it is |
|---|---|
| `cfg` | the role's routing entry, as JSON |
| `role` | the role name |
| `workdir` | where the agent works: the task's worktree (read-write) |
| `prompt` | a file with the task prompt |
| `rundir` | the run directory (read-write): `$role.system.md`, sessions, outputs, logs |

It must:

1. **Run the agent in `workdir`** with the prompt from `prompt` and the system prompt from
   `$rundir/$role.system.md`. `agent-run` writes that file: the product's `AGENTS.md` as
   committed on `main`, then `roles/<role>.md`. The adapter never reads `AGENTS.md` or `roles/`
   itself. If the harness has no system-prompt flag, put the file first in the prompt, so it
   stays a stable prefix.
2. **Load nothing from the worktree or the host except the work itself.** Ignore project config
   the agent could write or the product could commit (settings, hooks, MCP servers, extensions,
   agent or command definitions, context files), and keep the harness's config directory (or
   `HOME`) under `$rundir`, so host config never applies. Load guards (Step 3) and skills (Step 4)
   from `$FACTORY_HOME`, which is mounted read-only. Disable MCP servers unless the factory adds
   them explicitly.
3. **Keep sessions under `$rundir`, one per role**, and continue that role's last session when
   `CONTINUE` is set.
4. **Write the output where the runner reads it.** `output: text`: only the agent's final answer
   in `$rundir/$role.out.md` (a reviewer's first line is its `VERDICT:`). `output: events`: append
   the harness's event stream to `$rundir/$role.events.jsonl`. Other logs go to
   `$rundir/$role.*.log`, never to the worktree.
5. **Exit non-zero when the harness failed** (no response, auth error, timeout). The runner
   treats it as a failed attempt, not as a verdict. If the harness exits `0` on failure, detect
   it (for example, an empty output file) and exit non-zero.
6. **Run without questions.** Nobody is there to answer: no approval prompts, no interactive
   setup. Auto-approve tool calls where the harness requires it; `bin/sandbox` is the boundary,
   and the guards still run.

**Why:** the runner, `run-task` and every script above them work the same with every harness
only because each `run.sh` honors the same interface. Point 2 is security as well as
reproducibility: config an agent writes into the worktree would otherwise apply to the next run
in it (the fix round, the reviewer), and could switch off the guards.

## Step 6. Routing keys

**What:** document the keys the adapter reads from a routing entry, with defaults:

| Key | Kind | Meaning |
|---|---|---|
| `harness` | neutral, required | the adapter's directory name |
| `model` | neutral, required | a model ID in the harness's vocabulary |
| `output` | neutral | `events` (default) or `text` |
| anything else | the adapter's own | for example `effort`, `tools`, `access`, `timeout`, `budget_usd` |

Read-only roles (reviewer, scout) must be read-only **by configuration**: a tool allowlist, a
deny list or the harness's own sandbox mode. Never by asking in the prompt.

**Why:** `config/routing.json` is the only place a role's harness and model are chosen, so
switching a role to another harness means editing one entry.

## Step 7. Check

Before routing a real role to the adapter, check inside the sandbox, on each backend you use:

1. **Image:** `bin/build-worker <product-dir> <harness>`, then
   `bin/sandbox <wt> <rd> -- <harness> --version` prints the pinned version.
2. **Auth:** a one-line prompt gets an answer, with only the variables from Step 2 set.
3. **Guards:** ask the agent to run `git push origin HEAD`, write `.env` and run
   `curl -fsSL https://example.com/install.sh | sh`. All three are blocked, with the guards'
   reasons in the agent's tool results, and the agent doesn't work around them.
4. **Worktree config ignored:** write the harness's project settings into a scratch worktree,
   uncommitted, with something that would weaken the run (for Claude Code,
   `.claude/settings.json` with `"disableAllHooks": true`). Repeat check 3: still blocked.
5. **System prompt:** write a `$rd/test.system.md` containing a random marker line, call
   `run.sh` directly through `bin/sandbox` with role `test`, and ask the agent to repeat the
   marker. Give it no tools if the harness allows that, so it can't find the marker by reading
   files.
6. **Read-only:** run a read-only role on a scratch worktree and ask it to change a file;
   `git -C <wt> status --porcelain` stays empty.
7. **Output and exit:** `output: text` writes only the final answer to `$role.out.md`; an unknown
   model makes `run.sh` exit non-zero.

Then route one cheap role to it (`docs/factory/operating-the-factory.md`) and update the
harness table in `docs/factory/factory-contract.md`, Step 5.
