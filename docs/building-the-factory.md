# Building the Factory: A Hands-On Course

A practical path from "one agent, steered by hand" to "a factory that builds my product."
It skips what you already know (context files, skills, the basics of worktrees, delegating to
sub-agents) and focuses on the parts that turn those pieces into a system.

The factory is **independent of any harness or LLM provider**. Pi is used as the first harness
because it's minimal, scriptable and works with many providers. The design keeps Pi-specific
code in one thin adapter, so you can add or swap harnesses and models without rebuilding the
factory.

Each module has a **goal**, what to **build**, how to **try it** on the real product, and a
**done when** check. Don't move to the next module until you pass the check.

> Pi evolves quickly. The Pi commands here match its docs as of September 2026
> (`pi --help` and the docs in the `earendil-works/pi` repo). Check them against your installed version.

---

## Design rules

1. **Neutral core, thin adapters.** Anything that describes *how work is done* is plain files:
   Markdown, shell scripts and JSON. Skills, roles, task templates, guards, the verify contract
   and the orchestration scripts belong to the core. Only the adapter knows harness-specific
   flags and APIs.
2. **Scripts control the flow, models make judgments.** Batching, worktrees, verification,
   commits, retries and routing are deterministic code. Models write specs, plans, code and
   reviews, and triage reports.
3. **Gates live outside the harness.** "Done" means `scripts/verify` passed, checked by the
   runner *after* the agent exits. That works the same for every harness and model.
4. **Route models by role.** Every agent call names a *role*, such as planner, implementer or reviewer.
   A config file maps each role to a harness and model. Changing a model is a one-line config
   change that you can measure.
5. **Isolation is the security boundary.** Pi doesn't ask for approval before tool calls (by
   design), and other harnesses differ. Every worker command runs through `bin/sandbox`, which can
   use Podman, Docker, bubblewrap or nothing. Guards are defense in depth.

---

## The architecture: factory ≠ product

The factory and the product are **two separate repos** with a clear contract between them.

| | `factory-model` (this repo) | `<product>` (your project) |
|---|---|---|
| Holds | *How* work gets done: skills, roles, guards, routing, runner scripts, adapters, run logs, evals | *What* is being built: code, tests, product docs, specs |
| Knowledge | Process knowledge, the same for any project | Domain knowledge, specific to this project |
| Git history | Changes to the factory | Changes to the product |

**The contract** (what the factory expects from any product):

1. `AGENTS.md` at the product root: domain knowledge, layout, conventions. It's the most widely
   supported context-file name, and Pi loads it automatically. Add a `CLAUDE.md` symlink only if
   some harness needs that name.
2. `scripts/verify`: **one** command that exits `0` when the code is healthy (build, lint,
   types, tests). The factory only ever calls this command.
3. `docs/specs/`: where specs and task files live.

**How they connect:**

```
~/factory-model/          ← core + adapters + logs
~/projects/<product>/     ← the product
~/projects/<product>-wt/  ← worktrees for parallel workers (outside the product repo)
```

---

## Module 0: Scaffold the factory

**Goal:** the neutral core layout, plus Pi installed as the first adapter.

**Build:**

```
factory-model/
├── AGENTS.md                  # how to work ON the factory itself
├── package.json               # makes this repo a Pi package (adapter manifest only)
├── config/
│   ├── routing.json           # role → harness + model
│   └── sandbox-env            # env vars allowed into the sandbox
├── sandbox/
│   └── Containerfile          # worker image (Podman/Docker backends)
├── roles/                     # role prompts: planner.md, implementer.md, reviewer.md
├── skills/                    # Agent Skills (SKILL.md): spec, plan, orchestrate, retro
├── guards/                    # neutral guard scripts + their tests
├── bin/                       # sandbox, agent-run, run-task, fan-out, collect, eval
├── adapters/
│   └── pi/
│       ├── run.sh             # translates agent-run → pi CLI
│       └── extensions/
│           └── factory-guards.ts
├── templates/                 # task.md, product AGENTS.md, verify
├── evals/
├── runs/                      # run logs (gitignored)
└── docs/
    ├── from-conductor-to-orchestrator.md
    ├── building-the-factory.md
    └── factory-log.md
```

Install Pi and sign in to at least **two providers**, so model routing is real from the first day:

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
pi            # then /login, once per provider (or set API keys as environment variables)
pi --list-models
```

`package.json` exposes the neutral skills and the Pi guard extension as a Pi package:

```json
{
  "name": "factory-model",
  "private": true,
  "pi": {
    "extensions": ["./adapters/pi/extensions/factory-guards.ts"],
    "skills": ["./skills"]
  }
}
```

For interactive sessions, install the package globally so it doesn't touch the product repo.
Add `FACTORY_HOME` to your shell profile, because the guards need it:

```bash
pi install ~/factory-model
echo 'export FACTORY_HOME=~/factory-model' >> ~/.bashrc
```

Factory `AGENTS.md`: keep it short. Describe the layout and the design rules above, and add one rule:
*product-specific knowledge never goes here, and harness-specific code only goes in `adapters/`.*

**Done when:** `pi list` shows the package, `pi --list-models` shows models from two providers,
and `runs/` is in `.gitignore`.

---

## Module 1: Make the product agent-ready

**Goal:** the product meets the contract. This is the step people skip, and it's the one that
decides how much autonomy you can safely give later.

**Build (in the product repo):**

1. `scripts/verify`: a fast, non-interactive health check. For example:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   npm run lint
   npm run typecheck
   npm test -- --silent
   ```
   Make it quiet on success and specific on failure, because agents read its output.
   Aim for under 2 minutes. If the full suite is slow, add `scripts/verify --quick`.
2. `AGENTS.md`: architecture in about 10 lines, where things live, how to run and test,
   conventions, and "never touch" areas. Keep it under about 150 lines and link to deeper docs
   instead of pasting them. Write it for *any* model. Don't include tricks for one provider.
3. `docs/specs/`: an empty folder for now.

Save templates of both to `factory-model/templates/`.

**Try it:** start `pi` in the product with a *cheap* model and ask it: *"Break something small, run
scripts/verify, fix it, run verify again."* Then do the same with a model from the other provider.

**Done when:** cold-start agents from both providers find, run and understand `scripts/verify`
without you explaining anything.

---

## Module 2: Guardrails and sandbox

**Goal:** protection that doesn't depend on any one harness or isolation technology. You'll
use two layers:

1. **The sandbox (the boundary).** `bin/sandbox` runs a single command so it can only reach the
   worktree, its run directory, a read-only copy of the factory, and the environment variables
   you allow. It has no home directory, no SSH keys, no cloud or push credentials, and no other
   repos.
2. **Guards (defense in depth).** These are neutral scripts. Each takes an action, and if it
   refuses, it exits non-zero with a reason on stderr. The reason is written *for the model*.

### The sandbox wrapper

**What runs inside it:** every harness call (through `bin/agent-run`) and every
`scripts/verify` run, because verify executes code the agent wrote. **What stays on the host:**
you, the orchestrator, `fan-out`, `collect`, and the git commits the runner makes.

**Backends**, chosen with `SANDBOX=`:

| `SANDBOX` | Isolation | When |
|---|---|---|
| `podman` (default) | Rootless container, no daemon | **The default on Linux** |
| `docker` | Container | When Podman isn't available, or on macOS/Windows |
| `bwrap` | bubblewrap namespaces, no image | Fast and light. Node and Pi must be installed system-wide, or listed in `SANDBOX_RO_PATHS` |
| `none` | Nothing | **Only** while developing the factory itself |

**Mount layout.** Paths are mounted at the **same absolute paths** inside the sandbox, so no
script has to translate paths:

| Path | Access | Why |
|---|---|---|
| `$FACTORY_HOME` | read-only | Agents can't change their own guards, roles or routing |
| worktree | read-write | The only code the agent may change |
| run directory | read-write | Briefs, logs, sessions, reports |
| repo's shared `.git` | read-only | Lets `git status` and `git diff` work inside the worktree, but not rewrite history |
| this worktree's own git dir | read-write | Its index and HEAD |

`config/sandbox-env` lists the **names** of the variables allowed in, one per line:

```
# provider keys the workers need, nothing else
ANTHROPIC_API_KEY
OPENAI_API_KEY
```

Inside the sandbox, Pi can't see the sign-ins you made with `/login` on the host, so workers
authenticate with these API keys. Don't add npm, GitHub or cloud tokens here.

`bin/sandbox`:

```bash
#!/usr/bin/env bash
# usage: sandbox [--net open|none] <workdir> <rundir> -- <command> [args...]
# Runs <command> in <workdir>, isolated per $SANDBOX (podman|docker|bwrap|none).
set -euo pipefail
FACTORY_HOME="${FACTORY_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"; export FACTORY_HOME
mode="${SANDBOX:-podman}"
image="${SANDBOX_IMAGE:-factory-worker:latest}"
net=open; if [ "$1" = --net ]; then net=$2; shift 2; fi
wt=$1; rundir=$2; shift 2; [ "$1" = -- ] && shift

# git metadata: shared repo read-only, this worktree's own git dir writable
common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
own=$(git -C "$wt" rev-parse --path-format=absolute --git-dir)

# env allowlist: config/sandbox-env + what the factory scripts themselves need
mapfile -t names < <(grep -Ev '^[[:space:]]*(#|$)' "$FACTORY_HOME/config/sandbox-env")
names+=(FACTORY_HOME CONTINUE)

case "$mode" in
  none)
    cd "$wt"; exec "$@" ;;

  podman|docker)
    args=(run --rm -i -w "$wt" -e HOME=/tmp
          -v "$FACTORY_HOME:$FACTORY_HOME:ro" -v "$wt:$wt" -v "$rundir:$rundir"
          -v "$common:$common:ro" -v "$own:$own")
    [ "$net" = none ] && args+=(--network none)
    if [ "$mode" = podman ]; then args+=(--userns=keep-id)          # files stay owned by you
    else args+=(--user "$(id -u):$(id -g)"); fi
    for n in "${names[@]}"; do [ -n "${!n:-}" ] && args+=(-e "$n"); done
    exec "$mode" "${args[@]}" "$image" "$@" ;;

  bwrap)
    args=(--ro-bind /usr /usr --ro-bind /etc /etc
          --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib64 /lib64
          --proc /proc --dev /dev --tmpfs /tmp)
    for p in ${SANDBOX_RO_PATHS:-}; do args+=(--ro-bind "$p" "$p"); done   # e.g. a user-level Node install
    args+=(--ro-bind "$FACTORY_HOME" "$FACTORY_HOME" --bind "$wt" "$wt" --bind "$rundir" "$rundir"
           --ro-bind "$common" "$common" --bind "$own" "$own"
           --unshare-all --die-with-parent --clearenv
           --setenv HOME /tmp --setenv PATH "$PATH" --chdir "$wt")
    [ "$net" = open ] && args+=(--share-net)
    for n in "${names[@]}"; do [ -n "${!n:-}" ] && args+=(--setenv "$n" "${!n}"); done
    exec bwrap "${args[@]}" "$@" ;;

  *)
    echo "sandbox: unknown SANDBOX='$mode' (podman|docker|bwrap|none)" >&2; exit 2 ;;
esac
```

Mounts are applied in order, so the writable run directory (inside the factory's `runs/`) and the
worktree's own git dir end up writable even though their parent directories are mounted read-only.

`sandbox/Containerfile`, the worker image for the Podman and Docker backends:

```dockerfile
FROM node:22-bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends git jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent@<pinned-version>
# + your product's toolchain (compilers, test runners, etc.)
```

```bash
podman build -t factory-worker:latest -f sandbox/Containerfile sandbox/
docker build -t factory-worker:latest -f sandbox/Containerfile sandbox/   # same file, same syntax
```

`Containerfile` is the vendor-neutral name for a Dockerfile, with identical syntax. Podman finds it
automatically. Docker only looks for `Dockerfile` by default, which is why both commands pass
`-f` explicitly. Two parts of the file are placeholders: `<pinned-version>` (put the exact Pi
version here) and the comment where your product's toolchain goes.

**Network.** `--net none` cuts all network access. The runner uses it for `scripts/verify`, so tests can't
send data out. If your tests need a database, run it as a service the sandbox can reach, or add
a `SANDBOX_VERIFY_NET` option. Agent calls need access to the provider APIs, so they use `open`.
The next hardening step is to route agent traffic through a proxy that only allows
specific domains (your LLM providers and package registry). Put `HTTPS_PROXY` in `config/sandbox-env`
and put the container on a network where the proxy is the only way out.

**Try the sandbox before anything else.** Create a scratch worktree and run the following. Each command should fail or show nothing sensitive:

```bash
wt=~/projects/<product>-wt/sandbox-test; rd=/tmp/sbx; mkdir -p "$rd"
git -C ~/projects/<product> worktree add -q -b sandbox-test "$wt" main
bin/sandbox "$wt" "$rd" -- ls -la ~/.ssh                    # nothing there
bin/sandbox "$wt" "$rd" -- env                              # only allowlisted vars
bin/sandbox "$wt" "$rd" -- touch "$FACTORY_HOME/x"          # read-only → fails
bin/sandbox "$wt" "$rd" -- git -C "$wt" status              # works
bin/sandbox --net none "$wt" "$rd" -- curl -sI https://example.com   # fails
```

Run the same checks with `SANDBOX=bwrap` and compare.

### Neutral guard scripts

`guards/bash.sh`:

```bash
#!/usr/bin/env bash
# usage: bash.sh "<command>"   → exit 0 = allow, exit 2 = block (reason on stderr)
cmd="$1"
if grep -Eq 'git push|rm -rf /|--force|curl .*\| *(ba)?sh' <<<"$cmd"; then
  echo "Blocked by factory: '$cmd' is not allowed. The runner handles git pushes; don't push yourself." >&2
  exit 2
fi
exit 0
```

`guards/files.sh`: same shape, takes a file path, and blocks `.env*`, lockfiles and migrations that
have already run.

`guards/test.sh`: runs each guard against a list of commands and paths that should be allowed
and should be blocked. **Test guards outside the harness first.** Most "my hook doesn't work"
problems are really bugs in the guard script itself.

### The Pi adapter for guards

`adapters/pi/extensions/factory-guards.ts` only translates Pi events into calls to the guard scripts:

```ts
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const GUARDS = join(process.env.FACTORY_HOME ?? "", "guards");

function check(script: string, arg: string) {
  const r = spawnSync(join(GUARDS, script), [arg], { encoding: "utf8" });
  if (r.status === 0) return undefined;
  return { block: true, reason: r.stderr.trim() || `Blocked by factory guard ${script}` };
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (event.toolName === "bash") return check("bash.sh", event.input?.command ?? "");
    if (event.toolName === "edit" || event.toolName === "write")
      return check("files.sh", event.input?.path ?? ""); // check the path field name in Pi's tool schema
  });
}
```

Adding another harness later means writing one more small wrapper around the same scripts, such as a
Claude Code hook that reads JSON from stdin, or another harness's plugin API.

### Why guards fail silently (in any harness)

| Symptom | Usual cause |
|---|---|
| Guard never fires | The extension or hook loads at session start, so restart. For project-local config, the harness may also require trust approval |
| Fires but doesn't block | The guard returns the wrong thing. In Pi, return `{ block: true, reason }`. Other harnesses use exit codes such as `2` |
| Model keeps retrying the same thing | The reason says *what* is blocked but not *what to do instead* |
| Works interactively but not in the sandbox | `FACTORY_HOME` or `PATH` is missing inside the sandbox, or the guards directory isn't mounted |

**Try it:** start Pi *inside* the sandbox,
`bin/sandbox "$wt" "$rd" -- pi --no-extensions -e "$FACTORY_HOME/adapters/pi/extensions/factory-guards.ts"`,
then ask the agent to `git push`, to edit `.env`, to `curl … | sh`, and to read `~/.ssh`.

**Done when:** the sandbox checks behave as expected on at least two backends, `guards/test.sh`
passes, the first three attempts are blocked by guards with a reason the agent follows, and the
fourth finds nothing because the sandbox hides it.

---

## Module 3: The runner, model routing and the verify gate

**Goal:** one neutral command runs any role on any harness and model, and nothing counts as
"done" unless `scripts/verify` passes.

### Routing config

`config/routing.json` (replace the placeholders with IDs from `pi --list-models`):

```json
{
  "roles": {
    "planner":            { "harness": "pi", "model": "<provider-A>/<strongest-reasoning-model>:high", "output": "events" },
    "implementer":        { "harness": "pi", "model": "<provider-B>/<cost-efficient-coding-model>:medium", "output": "events" },
    "implementer-strong": { "harness": "pi", "model": "<provider-A>/<strongest-coding-model>:high", "output": "events" },
    "reviewer":           { "harness": "pi", "model": "<provider-A>/<strong-model>:high",
                            "tools": "read,grep,find,ls", "output": "text" },
    "scout":              { "harness": "pi", "model": "<any>/<cheap-long-context-model>:off",
                            "tools": "read,grep,find,ls", "output": "text" }
  }
}
```

Routing principles:
- **Planner:** use the strongest reasoning model, because planning mistakes multiply.
- **Implementer:** use the cheapest model that passes your evals (Module 8). Retry failures on
  `implementer-strong`.
- **Reviewer:** use a **different model family than the implementer**. Models from the same
  family tend to share blind spots, and cross-family review catches more.
- **Scout** (searching and summarizing a codebase): use a cheap, fast, long-context model.
- **Read-only roles get read-only tools**, enforced by the tool allowlist rather than by the prompt.

### Role prompts

`roles/implementer.md`, `roles/reviewer.md` and so on are plain Markdown that gets added to the
system prompt. For example, `roles/reviewer.md`:

```markdown
You did not write this code. Assume it's wrong until shown otherwise.
You are given a task file and a diff file. Check the diff against every acceptance criterion.
Look for: missed criteria, untested paths, scope creep, broken conventions, security issues.
Your first line must be exactly `VERDICT: approve` or `VERDICT: changes-needed`.
Then list findings as `file:line: problem`. No praise.
```

Keep role prompts **model-neutral**: plain instructions, an explicit output format, and nothing
that relies on one provider's quirks.

### `bin/agent-run`: the only way the factory calls a model

```bash
#!/usr/bin/env bash
# usage: agent-run <role> <workdir> <prompt-file> <run-dir>
set -euo pipefail
export FACTORY_HOME="${FACTORY_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
role=$1; workdir=$2; prompt=$3; rundir=$4
cfg=$(jq -ec --arg r "$role" '.roles[$r]' "$FACTORY_HOME/${ROUTING:-config/routing.json}")
harness=$(jq -r .harness <<<"$cfg")
mkdir -p "$rundir"
echo "$(date -Is) $role $(jq -r .model <<<"$cfg") sandbox=${SANDBOX:-podman}" >> "$rundir/calls.log"
exec "$FACTORY_HOME/bin/sandbox" "$workdir" "$rundir" -- \
     "$FACTORY_HOME/adapters/$harness/run.sh" "$cfg" "$role" "$workdir" "$prompt" "$rundir"
```

The harness always runs inside `bin/sandbox`, so every role, model and harness gets the same
isolation. Prompt files have to be inside the worktree or the run directory, because nothing
else is mounted.

### `adapters/pi/run.sh`: the Pi translation

```bash
#!/usr/bin/env bash
set -euo pipefail
cfg=$1; role=$2; workdir=$3; prompt=$4; rundir=$5
model=$(jq -r .model <<<"$cfg")
tools=$(jq -r '.tools // "read,bash,edit,write,grep,find,ls"' <<<"$cfg")
output=$(jq -r '.output // "events"' <<<"$cfg")

args=(--model "$model" --tools "$tools"
      --no-approve                                # ignore project-local .pi config the agent could have written
      --no-extensions -e "$FACTORY_HOME/adapters/pi/extensions/factory-guards.ts"
      --no-skills --skill "$FACTORY_HOME/skills"  # same skills every run, whatever is installed
      --append-system-prompt "$FACTORY_HOME/roles/$role.md"
      --session-dir "$rundir/sessions/$role")
[ -n "${CONTINUE:-}" ] && args+=(--continue)

cd "$workdir"
if [ "$output" = text ]; then
  pi -p "${args[@]}" "$(cat "$prompt")" > "$rundir/$role.out.md"
else
  pi --mode json "${args[@]}" "$(cat "$prompt")" >> "$rundir/$role.events.jsonl"
fi
```

Explicit flags make every run **reproducible**: the same guards, skills and role prompt no matter
what is installed on the machine.

### `bin/run-task`: implement one task, gated by verify

```bash
#!/usr/bin/env bash
# usage: run-task <worktree> <task-file> <run-dir>   (task-file: a path inside the worktree)
set -euo pipefail
FACTORY_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export FACTORY_HOME
wt=$1; task=$2; rundir=$3; mkdir -p "$rundir"
run() { "$FACTORY_HOME/bin/agent-run" "$@"; }
verify() { "$FACTORY_HOME/bin/sandbox" --net none "$wt" "$rundir" -- scripts/verify > "$rundir/verify.log" 2>&1; }

printf 'Complete the task in %s. Write REPORT.md as it specifies.\n' "$task" > "$rundir/brief.md"
run implementer "$wt" "$rundir/brief.md" "$rundir" || true

status=red
for role in implementer implementer implementer-strong; do      # 2 fix rounds, then escalate
  if verify; then status=green; break; fi
  { echo "scripts/verify failed. Fix the cause (don't weaken the tests). Output:"; tail -60 "$rundir/verify.log"; } > "$rundir/fix.md"
  if [ "$role" = implementer ]; then CONTINUE=1 run "$role" "$wt" "$rundir/fix.md" "$rundir" || true
  else run "$role" "$wt" "$rundir/fix.md" "$rundir" || true; fi
done
[ $status = red ] && verify && status=green
echo "$status" > "$rundir/status"
```

The gate is outside the harness, so it works the same with any model. The model can't declare
itself done. Only `scripts/verify` decides.

**Try it:** give one small task to `run-task` on a fresh worktree. Then break the task on purpose
(ask for something the tests will reject) and watch the fix rounds and the escalation happen.

**Done when:** you switch the implementer to another provider by editing only `routing.json`,
and the same task still goes green.

---

## Module 4: The spec → task pipeline (skills)

**Goal:** turn an idea into **task files**. Each one is a self-contained brief that a cold-start
agent can finish and verify on its own. Task files are the factory's work orders.

**Build:**

`templates/task.md`:

```markdown
---
id: 012-csv-export
spec: docs/specs/004-reporting.md
depends_on: []
touches: [src/reports/, src/api/export.ts]   # used to spot parallel conflicts
---
## Goal
One or two sentences.
## Context
Files to read first. Relevant decisions. What already exists.
## Constraints / out of scope
## Acceptance criteria
- [ ] Checkable items, each backed by a test where possible
- [ ] scripts/verify passes
## Report
Write REPORT.md at the worktree root: what changed, decisions made, open questions, anything left undone.
```

**Skills** in the Agent Skills format (`skills/<name>/SKILL.md` with `name` and `description`
frontmatter), which Pi and many other harnesses support:

- `skills/spec/`: interviews you about a feature (goal, users, constraints, non-goals, edge
  cases) and writes `docs/specs/NNN-name.md`. It asks questions and does **not** write code.
- `skills/plan/`: reads a spec and the codebase, then writes task files to
  `docs/specs/NNN-name/tasks/`. Rules for it: each task fits in one session, can be checked on
  its own, lists its `touches`, and sets `depends_on` honestly. It flags tasks whose `touches`
  overlap. It can use the `scout` role, through `bin/agent-run`, to summarize unfamiliar code.

Run both interactively in Pi with the planner's model:
`pi --model <planner-model>`.

**Try it:** write a spec for a real, small feature of your product and plan it into 3–5 tasks.
Then read every task file and ask yourself: *"Could a new contractor do this from this file alone?"*

**Done when:** `run-task` completes one of those task files with no extra words from you.

---

## Module 5: Cross-model review

**Goal:** a second model family checks every green branch before you see it.

**Extend `bin/run-task`** after the verify gate:

```bash
if [ $status = green ]; then
  git -C "$wt" add -A && git -C "$wt" commit -qm "factory: $(basename "$task" .md)"
  git -C "$wt" diff main...HEAD > "$rundir/diff.patch"
  printf 'Task: %s\nDiff: %s\n' "$task" "$rundir/diff.patch" > "$rundir/review-brief.md"
  run reviewer "$wt" "$rundir/review-brief.md" "$rundir" || true
  head -1 "$rundir/reviewer.out.md"                    # VERDICT: …
fi
```

The runner commits and builds the diff, so the reviewer needs no write or bash tools. Its
read-only access is enforced by `routing.json`, not by asking nicely.

If the verdict is `changes-needed`, the findings become a new fix brief for the implementer,
followed by verify and review again. Allow at most 2 rounds, then escalate to you.

**Try it:** run 3 tasks with the reviewer on the same family as the implementer, then 3 with a
different family. Compare the findings.

**Done when:** the reviewer finds at least one real issue you would otherwise have caught by hand.

---

## Module 6: Fan-out, where you stop talking to each agent

**Goal:** this is the change from what you do now. Workers run headless in parallel. You don't
chat with them. They take a task file as input and give back a branch, `REPORT.md`, a verify
status and a review verdict. **You read reports, not transcripts.**

**Build** `bin/fan-out`:

```bash
#!/usr/bin/env bash
# usage: fan-out <product-dir> <task-file>...   (task paths relative to the product root, committed on main)
set -euo pipefail
FACTORY_HOME="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT="$(cd "$1" && pwd)"; shift
RUN="$FACTORY_HOME/runs/$(date +%Y%m%d-%H%M%S)"
for task in "$@"; do
  id=$(basename "$task" .md); wt="${PRODUCT}-wt/$id"
  git -C "$PRODUCT" worktree add -q -b "factory/$id" "$wt" main
  "$FACTORY_HOME/bin/run-task" "$wt" "$wt/$task" "$RUN/$id" &
done
wait
echo "Run complete: $RUN"
```

`run-task` itself stays on the host. Every agent call and every verify run inside it goes
through `bin/sandbox`, so each worktree gets its own isolated sandbox. Task files have to be
committed on `main` before fan-out, so each worktree contains its own copy. That copy is the
path the agent is given, because it's the only one mounted in the sandbox.

**Build** `bin/collect`: for each task in a run, print the id, the status (green or red), the review
verdict, the `REPORT.md` summary and open questions, the diff stat, and the models used (from
`calls.log`). This is your dashboard.

Rules:
- Only run tasks together if their `touches` don't overlap and they don't depend on each other.
- Nothing is pushed or merged by agents. The runner commits to local branches, and you merge.

**Try it:** fan out 2–3 independent tasks from Module 4. Go do something else. Come back and run
`collect`.

**Done when:** you get through a whole batch without opening any worker's session.

---

## Module 7: The orchestrator, and the loop that improves the factory

**Goal:** one lead session runs the pipeline, and every failure improves the factory.

### 7a. Orchestrator skill

`skills/orchestrate/SKILL.md`, run interactively with the planner's model. Following rule 2 of
the design rules, it only *calls* the scripts and makes the judgments:

1. Reads the task files and builds batches from `depends_on` and `touches`.
2. Runs `bin/fan-out` for each batch and `bin/collect` afterwards.
3. Triages the results. It answers questions it can answer from the spec, rewrites unclear task
   files, and re-queues failures.
4. Shows **you** only: branches ready to merge, questions that need you, and escalations.
5. **Human gate:** it never merges. You merge, then clean up with `git worktree remove` and
   delete the branch.

The same flow runs in any harness that can read a skill and run bash, so the orchestrator
isn't tied to Pi either.

### 7b. The factory log

`docs/factory-log.md`: one line for each time something went wrong. **Include the model**,
because failures often depend on the model:

```
2026-10-03 | 012-csv-export | implementer=<model> | edited unrelated files | cause: task Context too vague | fix: plan skill now requires explicit `touches`
```

Classify every failure and fix it in **the matching layer**:

| Failure type | Fix goes into |
|---|---|
| Agent didn't know something about the product | product `AGENTS.md` |
| Agent did a procedure wrong or inconsistently | a skill or role prompt |
| Agent did something that must *never* happen | a guard (plus a case in `guards/test.sh`) |
| Bad code passed | a test, `scripts/verify`, or the reviewer role |
| Task was badly scoped | the `plan` skill rules / task template |
| One model keeps failing one kind of task | `routing.json` |

`skills/retro/`: reads recent `runs/`, reports and the factory log, then proposes concrete
factory changes. You approve them.

**Done when:** you give it a spec, get back reviewed merge-ready branches, and your only work
is answering questions and merging. You've also made at least 3 factory improvements from the
log.

---

## Module 8: Measure the factory

**Goal:** routing and prompt changes are decided by numbers.

**Build:**
- `evals/`: 5–10 frozen tasks against a fixed product commit, each with hidden acceptance
  tests.
- `bin/eval [--routing config/routing.alt.json]`: runs every eval task through `run-task` and
  scores pass or fail against the hidden tests.
- Metrics per **role × model**: pass rate, fix rounds, escalation rate, review findings,
  cost, and wall time. Pi's JSON event stream (`--mode json`) gives you the per-run data.

**Try it:** run the evals with two implementer models, or with a local model against a cloud
model. Keep whichever wins on cost per passed task.

**Done when:** a change to `routing.json` or a role prompt is backed by eval numbers.

---

## Order and pacing

| Module | What you gain |
|---|---|
| 0–1 | The neutral factory exists and the product is agent-ready |
| 2 | Isolation and guards that work with any harness |
| 3 | **One runner, any model, done means verified (the foundation)** |
| 4–5 | Repeatable work orders and cross-model review |
| 6 | Real parallelism without chatting to each agent |
| 7 | An orchestrator, and a factory that improves itself |
| 8 | Model routing and factory changes decided by data |

Adding a second harness later means writing `adapters/<name>/run.sh` and one small guard
wrapper. Nothing else changes.
