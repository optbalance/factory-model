# Building the Factory: A Hands-On Course

A practical path from "one agent, steered by hand" to "a factory that builds my product."
It skips what you already know (context files, skills, the basics of worktrees, delegating to
sub-agents) and focuses on the parts that turn those pieces into a system.

The factory is **independent of any harness or LLM provider**. It is one factory with one thin
adapter per harness in `adapters/<name>/`, not one factory per harness. This course covers four:

| Harness | Why use it | Models |
|---|---|---|
| **Pi** (first) | Minimal, scriptable, works with many providers | Almost any |
| **Claude Code** | Hooks map 1:1 onto the guard scripts; the only legitimate way to use a Claude subscription (see `cost-strategy.md`) | Anthropic |
| **Codex** | A second model family, useful for the reviewer role | OpenAI |
| **Antigravity CLI (`agy`)** | A third model family; replaces Gemini CLI (it migrates Gemini CLI config) | Gemini. With a Google account plan, also some Claude and GPT-OSS models. With an API key (what workers use), Gemini only |

`config/routing.json` picks the harness per role, so you can mix them, for example an
implementer on Claude Code and a reviewer on Codex.

Each module has a **goal**, what to **build**, the **harness-specific steps** (Pi, Claude Code,
Codex, Antigravity), how to **try it** on the real product, and a **done when** check. This course
explains how to build the factory; to run it, use the short references `docs/factory/factory-contract.md`
(what the machine needs) and `docs/factory/operating-the-factory.md` (which command for which job). The neutral part is
done once. The harness-specific steps are done for each harness you use. Start with Pi, and add
the others once Module 3 passes. Don't move to the next module until you pass the check.

> Harnesses evolve quickly. Check every command here against your installed version:
> - Pi: its docs as of September 2026 (`pi --help` and the `earendil-works/pi` repo).
> - Claude Code: v2.1.288 (`claude --help`, `/hooks`, `claude plugin --help`).
> - Codex: the `codex exec` and hooks docs as of October 2026 (`codex exec --help`). Codex
>   wasn't installed when this was written, so its steps are untested.
> - Antigravity CLI: checked on 2026-10-08 against the official pages at `antigravity.google/docs/`
>   (`cli/install`, `cli/headless`, `cli/reference`, `cli/troubleshooting`, `hooks`, `permissions`,
>   `plugins`, `skills`, `rules`, `models`, `settings`). Only commands and keys from those pages are
>   used. `agy` wasn't installed when this was written, so its steps are untested. Where the docs
>   leave behavior open, the step is marked **test this**.

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
   design). Claude Code, Codex and Antigravity do, but inside the factory their approvals are
   turned off (`bypassPermissions` / `--dangerously-bypass-approvals-and-sandbox` /
   `--dangerously-skip-permissions`), because nobody is there to answer them. Every worker command runs through `bin/sandbox`, which can
   use Docker (the default), Podman, bubblewrap or nothing. Guards are defense in depth.

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
   supported context-file name, and Pi, Codex and Antigravity load it automatically. Claude Code reads
   `CLAUDE.md`, so add a `CLAUDE.md → AGENTS.md` symlink if you use it (Module 1).
2. `scripts/verify`: **one** command that exits `0` when the code is healthy (build, lint,
   types, tests). The factory only ever calls this command.
3. `docs/specs/`: where specs and task files live.
4. `toolchain.Containerfile`: the image the product builds and tests in (JDK and Gradle, Node,
   Go…). The factory never installs a product's toolchain itself. It builds its own layers on top
   of this image (Module 2). The image holds every dependency `main` declares, so verify runs
   offline.
5. `scripts/deps`: prints the product's direct dependencies with their versions, one per line.
   Tasks never change dependencies: those changes land on `main` first (Module 4). The runner
   compares the output before and after each task and stops a task that changed it (Module 3).
   Required when dependencies install into the worktree (npm, a venv), recommended otherwise.

**How they connect:**

```
~/factory-model/          ← core + adapters + logs
~/projects/<product>/     ← the product
~/projects/<product>-wt/  ← worktrees for parallel workers (outside the product repo)
```

---

## Module 0: Scaffold the factory

**Goal:** the neutral core layout, plus the adapters for the harnesses you use.

**Build:**

```
factory-model/
├── AGENTS.md                  # how to work ON the factory itself
├── package.json               # makes this repo a Pi package (Pi adapter manifest only)
├── config/
│   ├── routing.json           # role → harness + model
│   ├── routing.<name>.json    # alternative routings (e.g. routing.claude.json), copied over routing.json or passed to bin/eval
│   └── sandbox-env            # env vars allowed into the sandbox
├── sandbox/
│   └── Containerfile          # factory base layer of the worker image, FROM a product's toolchain image
├── roles/                     # role prompts: planner.md, implementer.md, reviewer.md
├── skills/                    # Agent Skills (SKILL.md): spec, plan, orchestrate, retro
├── guards/                    # neutral guard scripts + their tests
├── bin/                       # start, sandbox, build-worker, agent-run, run-task, fan-out, collect, eval, check-product, check-factory
├── adapters/
│   ├── pi/
│   │   ├── Containerfile      # Pi layer of the worker image
│   │   ├── run.sh             # translates agent-run → pi CLI
│   │   └── extensions/
│   │       └── factory-guards.ts
│   ├── claude/
│   │   ├── Containerfile      # Claude Code layer of the worker image
│   │   ├── run.sh             # translates agent-run → claude -p
│   │   └── plugin/            # Claude Code plugin: factory skills + guard hooks
│   │       ├── .claude-plugin/plugin.json
│   │       ├── skills -> ../../../skills
│   │       └── hooks/{hooks.json,guard.sh}
│   ├── codex/
│   │   ├── Containerfile      # Codex layer of the worker image
│   │   ├── run.sh             # translates agent-run → codex exec
│   │   ├── config.toml        # base config copied into each run's CODEX_HOME
│   │   ├── hooks.json
│   │   └── guard.sh
│   └── agy/
│       ├── Containerfile      # Antigravity layer of the worker image
│       ├── run.sh             # translates agent-run → agy -p
│       ├── settings.full.json, settings.read-only.json
│       └── plugin/            # Antigravity plugin: factory skills + guard hook
│           ├── plugin.json
│           ├── skills -> ../../../skills
│           ├── hooks.json
│           └── guard.sh
├── templates/                 # task.md, product AGENTS.md, verify, toolchain.Containerfile, deps (examples, copied by hand)
├── evals/
├── runs/                      # run logs (gitignored)
└── docs/
    ├── how-to/
    │   ├── from-conductor-to-orchestrator.md
    │   ├── building-the-factory.md
    │   ├── how-the-factory-works.md   # diagrams: directories, hosts and sandboxes, story → merge
    │   └── cost-strategy.md
    ├── factory/
    │   ├── factory-contract.md     # what the machine must provide (tools, sandbox, secrets)
    │   └── operating-the-factory.md # which command for which job
    └── factory-log.md
```

`bin/check-factory` checks this layout and creates anything missing (directories empty, files
empty). For `adapters/` it only checks the directory itself, because its content depends on which
harnesses you use. It skips `docs/`, which is documentation, not structure. It prints `All good, structure complete`, or the list of what it created.

Add `FACTORY_HOME` to your shell profile, because the guards need it in every harness:

```bash
echo 'export FACTORY_HOME=~/factory-model' >> ~/.bashrc
```

Factory `AGENTS.md`: keep it short. Describe the layout and the design rules above, and add one rule:
*product-specific knowledge never goes here, and harness-specific code only goes in `adapters/`.*

### Harness-specific steps

**Pi:**

1. Install Pi and sign in to at least **two providers**, so model routing is real from the first day:
   ```bash
   npm install -g --ignore-scripts @earendil-works/pi-coding-agent
   pi            # then /login, once per provider (or set API keys as environment variables)
   pi --list-models
   ```
2. `package.json` exposes the neutral skills and the Pi guard extension as a Pi package:
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
3. For interactive sessions, install the package globally so it doesn't touch the product repo:
   `pi install ~/factory-model`.

**Claude Code:**

1. Install it (the native installer from the Claude Code docs, or
   `npm install -g @anthropic-ai/claude-code`) and sign in with `claude` → `/login`.
2. Create the plugin that carries the factory into Claude Code. It's the counterpart of Pi's
   `package.json`:
   ```bash
   mkdir -p adapters/claude/plugin/{.claude-plugin,hooks}
   ln -s ../../../skills adapters/claude/plugin/skills      # the neutral skills, not a copy
   ```
   `adapters/claude/plugin/.claude-plugin/plugin.json`:
   ```json
   { "name": "factory", "version": "0.1.0", "description": "Factory skills and guards" }
   ```
   The hooks are added in Module 2.
3. For interactive sessions, load the plugin per session so nothing is written to the product
   repo. Save an alias for it in your shell profile, like `FACTORY_HOME`:
   ```bash
   echo "alias claude-factory='claude --plugin-dir ~/factory-model/adapters/claude/plugin'" >> ~/.bashrc
   source ~/.bashrc
   ```
   Start sessions with `claude-factory` when you want the factory's skills and guards. Skills then
   appear namespaced, as `/factory:spec`, `/factory:plan` and so on. Plain `claude` stays
   unchanged. Headless workers don't use the alias: `adapters/claude/run.sh` passes
   `--plugin-dir` itself.
4. Claude Code only runs Anthropic models. Your second provider for routing comes from Pi or Codex.

**Codex:**

1. Install it (`npm install -g @openai/codex`) and sign in with `codex login`, or use an API key.
2. Create `adapters/codex/config.toml`, the base config every run starts from:
   ```toml
   # copied into each run's CODEX_HOME by adapters/codex/run.sh
   [features]
   hooks = true
   ```
3. For interactive sessions, link the neutral skills into Codex's skills folder (one level deep):
   ```bash
   mkdir -p ~/.codex/skills
   for s in ~/factory-model/skills/*/; do ln -sfn "$s" ~/.codex/skills/; done
   ```
   If your Codex version ignores symlinked skills, copy them instead and re-copy after changes.
4. Codex only runs OpenAI models (plus local models with `--oss`).

**Antigravity (`agy`):**

1. Install it with the official installer, which puts the binary at `~/.local/bin/agy`:
   `curl -fsSL https://antigravity.google/cli/install.sh | bash`. Then run `agy` and sign in
   in the browser, and list the model slugs with `agy models`.
2. Create the plugin that carries the factory into `agy`. It works like the Claude Code plugin:
   ```bash
   mkdir -p adapters/agy/plugin
   ln -s ../../../skills adapters/agy/plugin/skills       # the neutral skills, not a copy
   ```
   `adapters/agy/plugin/plugin.json`:
   ```json
   { "name": "factory", "description": "Factory skills and guards" }
   ```
   `name` is required (letters, digits, `-` and `_`). The published schema allows no other
   fields, so don't add `version`. The docs also suggest a `$schema` key for editor autocomplete.
   Leave it out: its URL (`https://antigravity.google/schemas/v1/plugin.json`) returned 404 on
   2026-10-08, and the same schema's `additionalProperties: false` doesn't allow `$schema`
   itself. The hook is added in Module 2.
3. For interactive sessions, install the plugin from its local directory:
   ```bash
   agy plugin install ~/factory-model/adapters/agy/plugin
   agy plugin list                     # factory should be listed, with its skills
   ```
   Don't use `agy plugin link`. It works on plugin *marketplaces* (it needs a marketplace name
   and a target) and doesn't link a local folder.
4. `install` copies the plugin into `~/.gemini/antigravity-cli/plugins/factory/`, so reinstall
   after every change to the factory's skills or hooks:
   `agy plugin uninstall factory && agy plugin install ~/factory-model/adapters/agy/plugin`.
   **Test this:** whether the copy follows the relative `skills` symlink. If `agy plugin list`
   shows no skills, install from a resolved copy instead:
   `cp -rL ~/factory-model/adapters/agy/plugin /tmp/factory-plugin && agy plugin install /tmp/factory-plugin`.
5. Models depend on how you sign in. A Google account plan offers Gemini plus some Claude and
   GPT-OSS models (see the `models` page). An API key, which the sandboxed workers use
   (Module 2), gives Gemini only.

**Done when:** `runs/` is in `.gitignore`, and for each harness you use, its skills show up in an
interactive session (`pi list`, `/factory:` completion in Claude Code, `/skills` in Codex, `/` in
`agy`), and
across all of them you have models from at least two providers (`pi --list-models` alone is
enough when Pi is your only harness).

---

## Module 1: Make the product agent-ready

**Goal:** the product meets the contract. This is the step people skip, and it's the one that
decides how much autonomy you can safely give later.

**Build (in the product repo):**

1. `scripts/verify`: a fast, non-interactive health check. Make it quiet on success and specific on
   failure, because agents read its output. Aim for under 2 minutes. If the full suite is slow, add
   `scripts/verify --quick`.
2. `AGENTS.md`: architecture in about 10 lines, where things live, how to run and test,
   conventions, and "never touch" areas. Keep it under about 150 lines and link to deeper docs
   instead of pasting them. Write it for *any* model. Don't include tricks for one provider.
3. `docs/specs/`: an empty folder for now. Git doesn't track empty folders, so commit a
   `docs/specs/.gitkeep`.
4. `toolchain.Containerfile`: the image that `scripts/verify` and the agents' build and test
   commands run in. If the product already has a CI or dev-container image, this file can be a
   single `FROM` line that points at it. Its requirements are in the product contract (Step 6).
5. `scripts/deps`: lists the product's direct dependencies with their versions, so the runner can
   stop a task that changes them. Required when dependencies install into the worktree,
   recommended otherwise. See the template below.

Commit them on `main`. `fan-out` creates worktrees from `main`, so agents only see what's
committed there.

What each file must do, and why, is in `docs/product/product-contract.md`: that's the one place
to look when you plug in a product. This module shows the templates.

The templates below are **examples, not requirements**. Copy them to `factory-model/templates/`
(`verify`, `AGENTS.md`, `toolchain.Containerfile`, `deps`) as a starting point for new products,
and adapt them to each product. The factory only depends on the contract: `scripts/verify` exists,
runs without prompts, and exits `0` when the code is healthy, `toolchain.Containerfile` builds an
image it can run in, and `scripts/deps`, if present, lists the direct dependencies offline. `bin/check-product` (below) checks exactly that.

#### Template: `scripts/verify`

Shown for a Node project. Replace the `step` lines with your stack's commands (`cargo`, `go`,
`pytest`, `mvn`, …); the rest stays the same.

```bash
#!/usr/bin/env bash
# scripts/verify: the product's one health check. Exit 0 = healthy.
# usage: scripts/verify [--quick]
# Runs non-interactively and offline: the factory runs it in a sandbox with no network.
set -uo pipefail
cd "$(dirname "$0")/.."
export CI=true                     # most tools then skip prompts, colors and watch mode
quick=0; [ "${1:-}" = --quick ] && quick=1
log=$(mktemp); trap 'rm -f "$log"' EXIT

# step <name> <command...>: one line on success; on failure, the command and the end of its
# output, then stop. One failure at a time keeps the output short enough for an agent to act on.
step() {
  local name=$1; shift
  if "$@" >"$log" 2>&1; then
    echo "ok    $name"
  else
    echo "FAIL  $name: $*"
    tail -n 50 "$log"
    exit 1
  fi
}

# A fresh worktree has no installed dependencies, and verify can't download them.
[ -d node_modules ] || { echo "FAIL  dependencies: node_modules is missing. Run 'npm ci' first (needs network)."; exit 1; }

step lint       npm run --silent lint
step typecheck  npm run --silent typecheck
if [ "$quick" = 1 ]; then
  step "unit tests" npm run --silent test:unit
else
  step tests      npm test --silent
fi
echo "verify: all checks passed"
```

```bash
chmod +x scripts/verify && git add scripts/verify     # git records the executable bit
```

#### Template: `AGENTS.md`

Replace everything in `<angle brackets>`. Delete sections that don't apply rather than leaving
them empty.

````markdown
# <Product name>

<One sentence: what the product does and for whom.>

## Architecture

<About 10 lines: the main parts, how a request or job flows through them, where state lives,
and which external services it talks to.>

## Layout

- `src/<area>/`: <what lives here>
- `tests/`: <unit vs. integration tests, file naming>
- `scripts/verify`: the health check (see "Definition of done")
- `docs/specs/`: specs and task files

## Commands

- Install dependencies: `<npm ci>` (needs network)
- Run locally: `<npm run dev>`
- Check everything: `scripts/verify`. While iterating: `scripts/verify --quick`.

## Definition of done

Work is done only when `scripts/verify` exits 0. Never weaken, skip or delete tests to make it
pass. If a test is wrong, say so in your report instead of changing it.

## Conventions

- <Language and framework versions; style rules the linter doesn't enforce>
- <Error handling, logging, naming>
- <How tests are written: where they live, what they mock, what they don't>

## Never touch

- <Generated or vendored code: `src/generated/`, `vendor/`>
- <Applied database migrations; add a new migration instead>
- <Public API contracts, unless the task's spec says so>

## More docs

- `<docs/architecture.md>`: <when to read it>
````

#### Template: `toolchain.Containerfile`

Shown for a Node project, to match the verify template. Replace the base image and packages with
your stack's.

```dockerfile
# toolchain.Containerfile: the image the product builds and tests in.
# The factory builds it from main, with the repo root as build context, and adds its layers on top.
FROM docker.io/library/node:22-bookworm-slim
# + system packages the build or tests need, for example:
# RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
#  && rm -rf /var/lib/apt/lists/*
# + if the build tool downloads dependencies outside the worktree (Gradle, Maven, Cargo, Go…):
#   point its cache at a fixed path with ENV and pre-fetch everything main declares into it.
#   Node needs neither: node_modules is in the worktree.
```

The image's requirements, where to point each build tool's cache, and a Gradle example that
pre-fetches `main`'s dependencies are in `docs/product/product-contract.md`, Step 6. In short:
Debian or Ubuntu, usable by any user, caches at fixed paths, and complete offline for `main`.
Tasks never change dependencies, so the image is the only place a dependency outside the worktree
can come from.

#### Template: `scripts/deps`

Shown for a Node project:

```bash
#!/usr/bin/env bash
# scripts/deps: the product's direct dependencies with their declared versions, one per line, sorted.
# Offline, from the current directory. The runner compares its output before and after each task.
set -euo pipefail
jq -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries[] | "\(.key)@\(.value)"' package.json | sort -u
```

The rules it must follow, when it's required, and a Gradle version are in
`docs/product/product-contract.md`, Step 7.

#### Factory script: `bin/check-product`

This lives in the **factory**, not in the product. It checks a product against the contract the
way the runner sees it: from what's committed on `main`. With `--run`, it also runs
`scripts/verify` exactly as `bin/run-task` does, in a fresh worktree, sandboxed and offline. That
needs `bin/sandbox` and the product's worker image from Module 2, so use `--run` once that module
is done.

```bash
#!/usr/bin/env bash
# usage: check-product [--run] <product-dir>
# Checks that a product meets the factory contract, as committed on main (fan-out creates
# worktrees from main). --run also runs scripts/verify the way run-task does: in a fresh
# worktree, through bin/sandbox, with no network.
set -euo pipefail
FACTORY_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export FACTORY_HOME
run=0; if [ "${1:-}" = --run ]; then run=1; shift; fi
[ $# -eq 1 ] || { echo "usage: check-product [--run] <product-dir>" >&2; exit 2; }
p="$(cd "$1" && pwd)"
fails=0
ok()   { echo "ok    $*"; }
warn() { echo "warn  $*"; }
fail() { echo "FAIL  $*"; fails=$((fails + 1)); }

git -C "$p" rev-parse -q --verify "main^{commit}" >/dev/null 2>&1 \
  || { fail "$p is not a git repo with a 'main' branch"; exit 1; }

# AGENTS.md
if git -C "$p" cat-file -e main:AGENTS.md 2>/dev/null; then
  n=$(git -C "$p" show main:AGENTS.md | wc -l)
  if [ "$n" -le 150 ]; then ok "AGENTS.md ($n lines)"
  else warn "AGENTS.md has $n lines; aim for under ~150 and link to deeper docs"; fi
else
  fail "AGENTS.md is not committed on main"
fi

# scripts/verify: committed and executable (git mode 100755)
mode=$(git -C "$p" ls-tree main scripts/verify | cut -d' ' -f1)
case "$mode" in
  100755) ok "scripts/verify is committed and executable" ;;
  100644) fail "scripts/verify is not executable: chmod +x scripts/verify && git add scripts/verify, then commit" ;;
  "")     fail "scripts/verify is not committed on main" ;;
  *)      fail "scripts/verify has git mode $mode; it must be a regular executable file" ;;
esac

# docs/specs/
if git -C "$p" cat-file -e main:docs/specs 2>/dev/null; then ok "docs/specs/ exists"
else warn "docs/specs/ is not committed on main (add docs/specs/.gitkeep)"; fi

# toolchain.Containerfile: the base of the worker image (not used by the bwrap and none backends)
if git -C "$p" cat-file -e main:toolchain.Containerfile 2>/dev/null; then ok "toolchain.Containerfile exists"
else case "${SANDBOX:-docker}" in
  podman|docker) fail "toolchain.Containerfile is not committed on main; the worker image is built FROM it" ;;
  *)             warn "toolchain.Containerfile is not committed on main (only SANDBOX=podman|docker need it)" ;;
esac; fi

# scripts/deps: without it, run-task can't stop a task that changes dependencies
if git -C "$p" cat-file -e main:scripts/deps 2>/dev/null; then ok "scripts/deps exists"
else warn "scripts/deps is not committed on main; run-task can't stop a task that changes dependencies (required if they install into the worktree)"; fi

# CLAUDE.md -> AGENTS.md, only when some role runs on Claude Code
routing="$FACTORY_HOME/config/routing.json"
if [ -s "$routing" ] && jq -e 'any(.roles[]; .harness == "claude")' "$routing" >/dev/null 2>&1; then
  if [ "$(git -C "$p" ls-tree main CLAUDE.md | cut -d' ' -f1)" = 120000 ] \
     && [ "$(git -C "$p" cat-file -p main:CLAUDE.md)" = AGENTS.md ]; then
    ok "CLAUDE.md -> AGENTS.md"
  else
    fail "a role runs on Claude Code, but CLAUDE.md is not a committed symlink to AGENTS.md"
  fi
fi

# --run: verify in a fresh, sandboxed, offline worktree
if [ "$run" = 1 ]; then
  if [ "$mode" != 100755 ]; then
    warn "skipping --run: scripts/verify is not runnable"
  else
    wt="${p}-wt/check-product-$$"
    rundir="$FACTORY_HOME/runs/check-product-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$rundir"
    trap 'git -C "$p" worktree remove --force "$wt" 2>/dev/null || true' EXIT
    git -C "$p" worktree add -q --detach "$wt" main
    start=$SECONDS
    if "$FACTORY_HOME/bin/sandbox" --net none "$wt" "$rundir" -- scripts/verify > "$rundir/verify.log" 2>&1; then
      ok "scripts/verify passed in a fresh offline worktree ($((SECONDS - start))s)"
    else
      fail "scripts/verify failed in a fresh offline worktree (full log: $rundir/verify.log):"
      tail -n 20 "$rundir/verify.log" | sed 's/^/      /'
    fi
    [ $((SECONDS - start)) -le 120 ] || warn "verify took over 2 minutes; consider scripts/verify --quick"
    if git -C "$p" cat-file -e main:scripts/deps 2>/dev/null; then
      if n=$("$FACTORY_HOME/bin/sandbox" --net none "$wt" "$rundir" -- bash scripts/deps 2>"$rundir/deps.log" | wc -l) \
         && [ "$n" -gt 0 ]; then
        ok "scripts/deps lists $n dependencies, offline"
      else
        fail "scripts/deps failed or printed nothing in a fresh offline worktree (log: $rundir/deps.log)"
      fi
    fi
  fi
fi

if [ "$fails" -eq 0 ]; then echo "Product meets the factory contract."
else echo "$fails check(s) failed."; exit 1; fi
```

```bash
chmod +x bin/check-product
bin/check-product ~/projects/<product>          # static checks
bin/check-product --run ~/projects/<product>    # + verify, sandboxed and offline (after Module 2 and bin/build-worker)
```

`FAIL` lines break the runner; `warn` lines don't, but they cost you agent quality or convenience.
If `--run` fails only because dependencies are missing, that's also what the first verify in
`bin/run-task` sees: a fresh worktree has none, and verify runs offline. The implementer runs with
network access before verify, so it can install the ones that live in the worktree. The template's
message tells it how. Dependencies outside the worktree come with the toolchain image, so a
`--run` failure about them means the image doesn't pre-fetch everything `main` declares.

### Harness-specific steps

**Pi:**

1. Nothing to add. Pi loads `AGENTS.md` automatically.
2. Try it: `pi --model <cheap-model>` in the product.

**Claude Code:**

1. Add the symlink, so `AGENTS.md` stays the only source of truth:
   `ln -s AGENTS.md CLAUDE.md && git add CLAUDE.md`. Add it to `templates/` too.
2. Try it: `claude --model sonnet` (or `haiku`) in the product.

**Codex:**

1. Nothing to add. Codex loads `AGENTS.md` automatically.
2. Try it: `codex -m <cheap-model>` in the product.

**Antigravity (`agy`):**

1. Nothing to add. `agy` loads `AGENTS.md` automatically. It also reads `GEMINI.md`, but don't
   add one, so there's only one source of truth. It also loads global rules from
   `~/.gemini/AGENTS.md` and `~/.gemini/GEMINI.md`. Factory runs use their own `HOME`, so your
   personal global rules don't leak into them.
2. Try it: `agy --model <flash-slug-from-agy-models>` in the product.

**Try it:** start a harness in the product with a *cheap* model and ask it: *"Break something
small, run scripts/verify, fix it, run verify again."* Then do the same with a model from the
other provider, through whichever harness serves it.

**Done when:** `bin/check-product` passes for the product, and cold-start agents from both
providers find, run and understand `scripts/verify` without you explaining anything.

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

**What it runs in.** The agents build and test the product inside the sandbox, so the sandbox
needs the product's toolchain, the tools the factory core uses, and the harnesses. For the
container backends, the worker image is a stack of layers, each built `FROM` the one below it and
each owned by the part of the system it belongs to:

| Layer | Owner | Contents |
|---|---|---|
| Toolchain | Product: `toolchain.Containerfile` (contract item 4) | The OS and whatever the product needs to build and test |
| Base | Factory core: `sandbox/Containerfile` | git, jq, curl: what the agents, the hook wrappers and the installers need |
| One per harness | Adapter: `adapters/<harness>/Containerfile` | That harness and its runtime (Pi brings Node, Claude Code is a single binary) |

`bin/build-worker` stacks them into one worker image per product, `factory-worker-<product>`,
with only the harnesses you use. That's how a product gets plugged into the factory. The product
never mentions a harness, the core never names a product or a harness, and each harness's
install lives in its adapter.

The order isn't arbitrary. A Containerfile has exactly one `FROM`, so the bottom layer has to be
the one that can't be installed onto something else: the product's, which brings the OS and a
toolchain that could be anything. The factory's layers install onto any Debian or Ubuntu base.
The factory's *code* (guards, roles, adapters, routing) isn't in the image at all. `bin/sandbox`
mounts it read-only at run time, so changing a guard needs no rebuild.

**Backends**, chosen with `SANDBOX=`:

| `SANDBOX` | Isolation | When |
|---|---|---|
| `docker` (default) | Container | **The default.** Works on Linux, macOS and Windows |
| `podman` | Rootless container, no daemon | When you want rootless isolation without a daemon. Untested with this factory |
| `bwrap` | bubblewrap namespaces, no image | Fast and light. There's no image, so the host's `/usr` provides everything: the product's toolchain and the harness binaries (and Node, for Pi) must be installed system-wide, or listed in `SANDBOX_RO_PATHS` |
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

Inside the sandbox, no harness can see the sign-ins you made on the host, so workers
authenticate with variables from this list. Each harness adds its own names below. Don't add
npm, GitHub or cloud tokens here.

**Supplying the values.** The file holds names only, so it's committed. The values come from the
environment of whatever starts the factory scripts: your terminal, or the orchestrator session
you start from it, because each process passes its environment on to the ones it starts. The
factory never reads secret files itself. Keep the values in a file outside every repo that only
your user can read, and start the orchestrator through `bin/start`, which loads it:

```bash
install -m 600 /dev/null ~/.config/factory/env     # once; then add NAME=value lines with an editor
bin/start claude                                   # the orchestrator, or any command, with the values loaded
```

`bin/start` (set `FACTORY_ENV` to use another file):

```bash
#!/usr/bin/env bash
# usage: start <command> [args...]      e.g. bin/start claude
# Runs <command> (the orchestrator session, or a factory script) with the factory's secrets in its
# environment. Everything it starts inherits them, and bin/sandbox passes on the names listed in
# config/sandbox-env. Values: NAME=value lines in $FACTORY_ENV (default ~/.config/factory/env), mode 600.
set -euo pipefail
FACTORY_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export FACTORY_HOME
envfile="${FACTORY_ENV:-$HOME/.config/factory/env}"
[ $# -ge 1 ] || { echo "usage: start <command> [args...]   e.g. start claude" >&2; exit 2; }
[ -r "$envfile" ] \
  || { echo "start: $envfile not found. Create it with mode 600 (docs/how-to/building-the-factory.md, Module 2)" >&2; exit 1; }
[ -z "$(find "$envfile" -perm /077)" ] \
  || echo "start: $envfile is readable by other users; run: chmod 600 $envfile" >&2
set -a; . "$envfile"; set +a
exec "$@"
```

Mode `600` keeps the values from other users, not from programs running as you: the orchestrator
session and anything else you start can read them. `bin/sandbox` warns on stderr about each
listed name that isn't set, so a missing key shows up before the harness fails to authenticate.
The setup steps, with the variable each harness needs, are in `docs/factory/factory-contract.md`
(Steps 5–6).

`bin/sandbox`:

```bash
#!/usr/bin/env bash
# usage: sandbox [--net open|none] <workdir> <rundir> -- <command> [args...]
# Runs <command> in <workdir>, isolated per $SANDBOX (podman|docker|bwrap|none).
set -euo pipefail
FACTORY_HOME="${FACTORY_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"; export FACTORY_HOME
mode="${SANDBOX:-docker}"
net=open; if [ "$1" = --net ]; then net=$2; shift 2; fi
wt=$1; rundir=$2; shift 2; [ "$1" = -- ] && shift

# git metadata: shared repo read-only, this worktree's own git dir writable
common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
own=$(git -C "$wt" rev-parse --path-format=absolute --git-dir)

# worker image: one per product, named after the product repo (see bin/build-worker)
product=$(basename "$(dirname "$common")"); product=${product,,}; product=${product//[^a-z0-9._-]/-}
image="${SANDBOX_IMAGE:-factory-worker-$product}"

# env allowlist: config/sandbox-env + what the factory scripts themselves need
mapfile -t names < <(grep -Ev '^[[:space:]]*(#|$)' "$FACTORY_HOME/config/sandbox-env")
for n in "${names[@]}"; do   # a warning, not an error: some names are optional (HTTPS_PROXY)
  [ -n "${!n:-}" ] || echo "sandbox: $n (config/sandbox-env) is not set; start the orchestrator with bin/start, or the harness may fail to authenticate" >&2
done
names+=(FACTORY_HOME CONTINUE)

case "$mode" in
  none)
    cd "$wt"; exec "$@" ;;

  podman|docker)
    args=(run --rm -i -w "$wt" -e HOME=/tmp
          -v "$FACTORY_HOME:$FACTORY_HOME:ro" -v "$wt:$wt" -v "$rundir:$rundir"
          -v "$common:$common:ro" -v "$own:$own")
    [ "$net" = none ] && args+=(--network none)
    args+=(--user "$(id -u):$(id -g)")                              # files stay owned by you
    [ "$mode" = podman ] && args+=(--userns=keep-id)                 # rootless: map your ID to itself
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

The image name comes from the product repo's directory: a worktree's shared `.git` sits in the
product repo, so every worktree of `~/projects/shop` runs in `factory-worker-shop`. Set
`SANDBOX_IMAGE` to override it.

### The worker image

`sandbox/Containerfile`, the factory base layer:

```dockerfile
# Factory base layer: what the factory core needs in every worker (git for the agents, jq for the
# hook wrappers, curl for installers). Built FROM a product's toolchain image by bin/build-worker.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends git jq ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
ENTRYPOINT []
CMD ["bash"]
```

`USER root` is set for the installs in this layer and the harness layers above it, because the
toolchain image may switch to a non-root user. At run time, `bin/sandbox` picks the user anyway.
Clearing `ENTRYPOINT` lets the sandbox run its command directly.

Each adapter adds an `adapters/<harness>/Containerfile` with the same shape: `ARG BASE_IMAGE`,
`FROM ${BASE_IMAGE}`, then that harness's install. The harness-specific steps below give one per
harness. Pin the exact harness version in it, so every product's image runs the same harness.

`bin/build-worker` plugs a product into the factory:

```bash
#!/usr/bin/env bash
# usage: build-worker <product-dir> [harness...]
# Builds the worker image for one product, one layer at a time, each FROM the previous one:
#   toolchain   the product's toolchain.Containerfile, as committed on main
#   base        the factory base layer, sandbox/Containerfile
#   <harness>   adapters/<harness>/Containerfile, for each harness named (default: those in config/routing.json)
# Layers are tagged factory-worker-<product>:<layer>; the last is also tagged :latest, which bin/sandbox runs.
set -euo pipefail
FACTORY_HOME="$(cd "$(dirname "$0")/.." && pwd)"
engine="${SANDBOX:-docker}"
case "$engine" in
  podman|docker) ;;
  *) echo "build-worker: SANDBOX=$engine uses no image" >&2; exit 2 ;;
esac
[ $# -ge 1 ] || { echo "usage: build-worker <product-dir> [harness...]" >&2; exit 2; }
p="$(cd "$1" && pwd)"; shift
product=$(basename "$p"); product=${product,,}; product=${product//[^a-z0-9._-]/-}   # as in bin/sandbox

harnesses=("$@")
routing="$FACTORY_HOME/config/routing.json"
if [ ${#harnesses[@]} -eq 0 ] && [ -s "$routing" ]; then
  mapfile -t harnesses < <(jq -r '[.roles[].harness] | unique[]' "$routing")
fi
[ ${#harnesses[@]} -gt 0 ] \
  || { echo "build-worker: name the harnesses, or list them in config/routing.json" >&2; exit 2; }
for h in "${harnesses[@]}"; do
  [ -f "$FACTORY_HOME/adapters/$h/Containerfile" ] \
    || { echo "build-worker: adapters/$h/Containerfile is missing" >&2; exit 2; }
done

# build from main, like fan-out: uncommitted changes never reach the image
src=$(mktemp -d); trap 'rm -rf "$src"' EXIT
git -C "$p" archive main | tar -x -C "$src"
[ -f "$src/toolchain.Containerfile" ] \
  || { echo "build-worker: toolchain.Containerfile is not committed on main in $p" >&2; exit 1; }

img="factory-worker-$product"
"$engine" build -t "$img:toolchain" -f "$src/toolchain.Containerfile" "$src"
prev=toolchain
for layer in base "${harnesses[@]}"; do
  if [ "$layer" = base ]; then dir="$FACTORY_HOME/sandbox"; else dir="$FACTORY_HOME/adapters/$layer"; fi
  "$engine" build -t "$img:$layer" --build-arg BASE_IMAGE="$img:$prev" -f "$dir/Containerfile" "$dir"
  prev=$layer
done
"$engine" tag "$img:$prev" "$img:latest"
echo "Built $img: toolchain, base, ${harnesses[*]}"
```

```bash
chmod +x bin/build-worker
bin/build-worker ~/projects/<product> pi                    # Docker (the default), with the harnesses named
SANDBOX=podman bin/build-worker ~/projects/<product> pi     # Podman: same files, same syntax
bin/build-worker ~/projects/<product>                       # after Module 3: the harnesses in routing.json
```

`Containerfile` is the vendor-neutral name for a Dockerfile, with identical syntax. Docker only
looks for `Dockerfile` by default, which is why `bin/build-worker` passes `-f` explicitly.

**Rebuild** after the product changes `toolchain.Containerfile` (or the dependencies it
pre-fetches) on `main`, after you change the base layer or a harness version, and after
`config/routing.json` starts using another harness. Builds are cached, and a change only rebuilds
its own layer and the ones above it. `bin/fan-out` (Module 6) runs `build-worker` before every
batch, so the image always matches `main`. That's cheap when nothing changed. Before Module 6,
rebuild by hand. If the image is missing, the first sandbox call fails with an "image not found"
error.

**Network.** `--net none` cuts all network access. The runner uses it for `scripts/verify`, so tests can't
send data out. If your tests need a database, run it as a service the sandbox can reach, or add
a `SANDBOX_VERIFY_NET` option. Agent calls need access to the provider APIs, so they use `open`.
The next hardening step is to route agent traffic through a proxy that only allows
specific domains (your LLM providers and package registry). Put `HTTPS_PROXY` in `config/sandbox-env`
and put the container on a network where the proxy is the only way out.

**Try the sandbox before anything else.** Build the product's worker image with the harnesses
you'll use, create a scratch worktree and run the following. The first four commands should fail or show nothing sensitive,
and the last two should work:

```bash
bin/build-worker ~/projects/<product> pi
wt=~/projects/<product>-wt/sandbox-test; rd=/tmp/sbx; mkdir -p "$rd"
git -C ~/projects/<product> worktree add -q -b sandbox-test "$wt" main
bin/sandbox "$wt" "$rd" -- ls -la ~/.ssh                    # nothing there
bin/sandbox "$wt" "$rd" -- env                              # only allowlisted vars
bin/sandbox "$wt" "$rd" -- touch "$FACTORY_HOME/x"          # read-only → fails
bin/sandbox --net none "$wt" "$rd" -- curl -sSI https://example.com  # fails: "Could not resolve host"
bin/sandbox "$wt" "$rd" -- git -C "$wt" status              # works
bin/sandbox "$wt" "$rd" -- <build-tool> --version          # the product's toolchain (gradle, node, go…)
```

Run the same checks with `SANDBOX=bwrap` and compare.

### Neutral guard scripts

Each guard takes one argument, exits `0` to allow and `2` to block, and writes its reason to
stderr. The reason is written **for the model**: what is blocked, and what to do instead.

`guards/bash.sh` checks a command before it runs:

```bash
#!/usr/bin/env bash
# usage: bash.sh "<command>"   → exit 0 = allow, exit 2 = block (reason on stderr)
# Each reason is written for the model: what is blocked, and what to do instead.
cmd="$1"
block() { echo "Blocked by factory: $1" >&2; exit 2; }

# git push, also with options before the subcommand (git -C <dir> push)
if grep -Eq '(^|[^[:alnum:]_./-])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+push\b' <<<"$cmd"; then
  block "don't push. The runner commits your work after verify passes, and a human merges it. Leave your changes in the worktree."
fi
# a download piped into a shell
if grep -Eq '\b(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh\b' <<<"$cmd"; then
  block "don't pipe a download into a shell. Tasks never install tools or dependencies: if one is missing, stop and say so under open questions in REPORT.md."
fi
# recursive delete of / or the home directory (paths inside the worktree are fine)
if grep -Eq '\brm[[:space:]]+([^;&|]*[[:space:]])?(-[[:alpha:]]*[rR][[:alpha:]]*|--recursive)\b[^;&|]*[[:space:]](/|~|\$HOME|\$\{HOME\})/?\*?([[:space:];&|]|$)' <<<"$cmd"; then
  block "don't delete / or the home directory. Delete only paths inside the worktree."
fi
exit 0
```

It blocks:

- **`git push`**, also with options before the subcommand (`git -C <dir> push`). The runner
  commits, and you merge.
- **A download piped into a shell** (`curl … | sh`). Tasks never install tools or dependencies.
- **A recursive delete of `/` or the home directory.** Paths inside the worktree are fine. Agents
  often use absolute paths, so the pattern must not block `rm -rf <worktree>/build`.

The patterns are deliberately narrow. A broad one (any `--force`, any `rm -rf /…`) blocks normal
work, and the model then wastes turns working around it. The sandbox is the boundary. Guards only
catch the obvious mistakes early, with a reason the model can follow.

`guards/files.sh` checks a path before the agent writes or edits it:

```bash
#!/usr/bin/env bash
# usage: files.sh "<path>"   → exit 0 = allow, exit 2 = block (reason on stderr)
# Checks a path an agent is about to write or edit, as given and with symlinks resolved. Relative
# paths are resolved against the current directory: the worktree, where the harness runs.
p="$1"
r=$(realpath -m -- "$p" 2>/dev/null || echo "$p")
block() { echo "Blocked by factory: $1" >&2; exit 2; }

for name in "${p##*/}" "${r##*/}"; do
  case "$name" in
    .env.example|.env.sample|.env.template) ;;
    .env|.env.*)
      block "don't write $p. Environment files hold secrets, and verify must not need one. Put example values in .env.example." ;;
    package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lock|bun.lockb|gradle.lockfile|*.lockfile|\
    Cargo.lock|go.sum|poetry.lock|Pipfile.lock|uv.lock|composer.lock|Gemfile.lock)
      block "don't edit $p by hand. Tasks never change dependencies: everything this task needs is already declared on main. If you need a change, stop and explain which one and why under open questions in REPORT.md." ;;
  esac
done

# harness config inside the worktree (the harness's own files under $HOME are fine)
harness='/(\.pi|\.claude|\.codex|\.agents|\.agent)/|/\.mcp\.json/$'
case "$r" in
  "$PWD"/*) [[ "/${r#"$PWD"/}/" =~ $harness ]] \
    && block "don't write harness config ($p). The factory configures the harness, and config in the worktree would change how later runs behave." ;;
esac
exit 0
```

It blocks:

- **`.env` files** (`.env`, `.env.local`, …). `.env.example`, `.env.sample` and `.env.template`
  are allowed, because they hold example values and a task that adds a setting should update them.
- **Hand edits of lockfiles** (`package-lock.json`, `yarn.lock`, `gradle.lockfile`, `Cargo.lock`…).
  Tasks never change dependencies (Module 3), so a task has no reason to edit one. The guard stops
  the most dangerous case early: a model writing lockfile text produces versions, hashes and
  download URLs that look right but aren't, in a diff too long for anyone to read. It only sees the
  agent's file-edit tools. A change made through a package manager is caught by the offline verify
  or the dependency gate (Module 3), and the reviewer flags any lockfile change in the diff.
- **Harness config inside the worktree** (`.pi/`, `.claude/`, `.codex/`, `.agents/`, `.agent/`,
  `.mcp.json`). An agent that writes harness config could change how the next run behaves. The
  harness's own files under `$HOME` (for example Claude Code's plans) are outside the worktree and
  allowed.

It checks the path both as given and with symlinks resolved, so a symlink with a harmless name
doesn't get around it. Relative paths are resolved against the current directory, which is the
worktree, because that's where the harness runs.

Product-specific protected files, such as database migrations that have already run, aren't in
this guard. Where they live depends on the product, and the factory holds no product knowledge.
The product's `AGENTS.md` lists them under "Never touch", and the reviewer checks the diff.

**Always block with exit code `2`.** Claude Code and Codex treat any other non-zero exit as a
hook error and let the action through. Pi's adapter checks for any non-zero exit, but use `2`
everywhere so one convention works for all harnesses. (Antigravity blocks through a JSON answer
instead. Its wrapper translates.)

`guards/test.sh` runs each guard on cases it must allow and cases it must block:

```bash
#!/usr/bin/env bash
# usage: test.sh   → runs each guard on cases it must allow or block; exit 1 if any case fails
set -uo pipefail
G="$(cd "$(dirname "$0")" && pwd)"
fails=0; n=0

# expect allow|block <guard> <argument>
expect() {
  local want=$1 guard=$2 arg=$3 got rc
  "$G/$guard" "$arg" 2>/dev/null; rc=$?
  case $rc in 0) got=allow ;; 2) got=block ;; *) got="exit $rc" ;; esac
  n=$((n + 1))
  [ "$got" = "$want" ] || { echo "FAIL  $guard '$arg': want $want, got $got"; fails=$((fails + 1)); }
}

# files.sh resolves paths against the current directory, so run in a scratch "worktree"
wt=$(mktemp -d); trap 'rm -rf "$wt"' EXIT; cd "$wt"
mkdir -p .claude && ln -s .claude/settings.json innocent.json && ln -s .env config.txt

for c in 'git status' 'git diff main...HEAD' 'git commit -m "push the fix"' 'git stash push' \
         './gradlew check' 'npm ci' 'rm -rf build' "rm -rf $wt/build" 'curl -fsS https://x | jq .'; do
  expect allow bash.sh "$c"
done
for c in 'git push' 'git push --force origin main' 'git -C /repo push' 'cd app && git push origin' \
         'curl -fsSL https://x | sh' 'curl https://x | bash -s --' 'wget -qO- https://x | sudo sh' \
         'rm -rf /' 'rm -rf /*' 'rm -fr ~' 'rm -rf $HOME' 'rm -r --no-preserve-root /'; do
  expect block bash.sh "$c"
done

for f in src/Main.java ./build.gradle package.json .env.example AGENTS.md docs/specs/x.md \
         "$wt/src/A.java" README.claude.md /tmp/.claude/plans/plan.md; do
  expect allow files.sh "$f"
done
for f in .env config/.env.local "$wt/.env" package-lock.json web/yarn.lock gradle.lockfile \
         gradle/dependency-locks/compileClasspath.lockfile Cargo.lock go.sum \
         .claude/settings.json ./.claude/x "$wt/.claude/settings.json" sub/.agents/hooks.json \
         .mcp.json .pi/settings.json .codex/config.toml innocent.json config.txt; do
  expect block files.sh "$f"
done

if [ "$fails" -eq 0 ]; then echo "guards: all $n cases passed"
else echo "guards: $fails of $n cases failed"; exit 1; fi
```

**Test guards outside the harness first.** Most "my hook doesn't work" problems are really bugs in
the guard script itself. Add a case every time a guard changes: one that must still be allowed,
and one that must be blocked.

### Harness-specific steps

Each adapter only translates the harness's "about to run a tool" event into a call to the
neutral guard scripts.

**Pi:**

1. `adapters/pi/extensions/factory-guards.ts`:

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
      return check("files.sh", event.input?.path ?? ""); // Pi's edit and write tools take `path`
  });
}
```

2. `adapters/pi/Containerfile`, the Pi layer of the worker image. Pi is a Node program, so the
   layer brings the factory's own Node. It keeps that Node off the `PATH`, so it never replaces a
   Node the product uses, and a product in another language doesn't get one. A small launcher runs
   Pi on it:
   ```dockerfile
   # Pi harness layer: Pi on the factory's own Node. Built FROM the factory base layer by bin/build-worker.
   ARG BASE_IMAGE
   FROM docker.io/library/node:22-bookworm-slim AS node
   FROM ${BASE_IMAGE}
   # The factory's Node lives off the PATH, so it never replaces a Node the product uses.
   COPY --from=node /usr/local/bin/node /opt/factory/node/bin/node
   COPY --from=node /usr/local/lib/node_modules/npm /opt/factory/node/lib/node_modules/npm
   RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /opt/factory/node/bin/npm \
    && PATH=/opt/factory/node/bin:$PATH npm install -g --ignore-scripts @earendil-works/pi-coding-agent@<pinned-version> \
    && printf '#!/bin/sh\nexec /opt/factory/node/bin/node %s "$@"\n' "$(readlink -f /opt/factory/node/bin/pi)" > /usr/local/bin/pi \
    && chmod +x /usr/local/bin/pi
   ```
3. For `SANDBOX=bwrap`, add your Node install to `SANDBOX_RO_PATHS` if it isn't system-wide
   (for example, an nvm directory).
4. Try it inside the sandbox:
   `bin/sandbox "$wt" "$rd" -- pi --no-extensions -e "$FACTORY_HOME/adapters/pi/extensions/factory-guards.ts"`.

**Claude Code:**

1. `adapters/claude/plugin/hooks/guard.sh`, a `PreToolUse` hook. Claude Code passes the tool call
   as JSON on stdin. Exit `2` blocks the call, and stderr is shown to the model:
   ```bash
   #!/usr/bin/env bash
   # PreToolUse hook: JSON on stdin → neutral guard. Exit 2 blocks; stderr goes to the model.
   in=$(cat)
   case "$(jq -r .tool_name <<<"$in")" in
     Bash) exec "$FACTORY_HOME/guards/bash.sh" "$(jq -r '.tool_input.command // ""' <<<"$in")" ;;
     Edit|Write|MultiEdit|NotebookEdit)
       exec "$FACTORY_HOME/guards/files.sh" \
            "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in")" ;;
   esac
   exit 0
   ```
2. `adapters/claude/plugin/hooks/hooks.json` registers it:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         { "matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit",
           "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh\"" }] }
       ]
     }
   }
   ```
   Because the hooks ship in the plugin, they run in every session that loads it, both
   interactive and headless.
3. `adapters/claude/Containerfile`, the Claude Code layer. The npm package is a single native
   binary, so the layer copies that binary out of a throwaway stage. npm only serves as the pinned
   download, and the worker gets no Node:
   ```dockerfile
   # Claude Code harness layer: the native binary only, no Node at run time. Built FROM the factory
   # base layer by bin/build-worker. npm is only the pinned download, in a throwaway stage.
   ARG BASE_IMAGE
   FROM docker.io/library/node:22-bookworm-slim AS claude
   RUN npm install -g @anthropic-ai/claude-code@<pinned-version>
   FROM ${BASE_IMAGE}
   COPY --from=claude /usr/local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe /usr/local/bin/claude
   ENV DISABLE_AUTOUPDATER=1
   ```
   `DISABLE_AUTOUPDATER` keeps the version you pinned. The updater couldn't replace a binary owned
   by root inside the sandbox anyway.
4. `config/sandbox-env`: `ANTHROPIC_API_KEY` for API billing, or `CLAUDE_CODE_OAUTH_TOKEN` for a
   subscription (create it on the host with `claude setup-token`). If both are set, the API key
   wins.
5. For `SANDBOX=bwrap` with the native installer, add `~/.local/bin` and `~/.local/share/claude`
   to `SANDBOX_RO_PATHS`.
6. Try it inside the sandbox:
   `bin/sandbox "$wt" "$rd" -- claude --plugin-dir "$FACTORY_HOME/adapters/claude/plugin" --setting-sources user`.
   Check with `/hooks` that the guard is registered.

**Codex:**

1. `adapters/codex/guard.sh`, a `PreToolUse` hook. File edits arrive as an `apply_patch` call
   whose `tool_input.command` is the patch text, so the wrapper pulls the paths out of it:
   ```bash
   #!/usr/bin/env bash
   # PreToolUse hook: JSON on stdin → neutral guards. Exit 2 blocks; stderr goes to the model.
   in=$(cat)
   cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
   case "$(jq -r .tool_name <<<"$in")" in
     Bash) exec "$FACTORY_HOME/guards/bash.sh" "$cmd" ;;
     apply_patch)
       grep -oP '^\*\*\* (Add|Update|Delete) File: \K.*|^\*\*\* Move to: \K.*' <<<"$cmd" |
         while read -r path; do "$FACTORY_HOME/guards/files.sh" "$path" || exit 2; done ;;
   esac
   ```
2. `adapters/codex/hooks.json` registers it:
   ```json
   {
     "hooks": {
       "PreToolUse": [
         { "matcher": "Bash|apply_patch|Edit|Write",
           "hooks": [{ "type": "command", "command": "$FACTORY_HOME/adapters/codex/guard.sh" }] }
       ]
     }
   }
   ```
   The adapter copies it into each run's `CODEX_HOME` (Module 3). For interactive use, copy it to
   `~/.codex/hooks.json` and approve it with `/hooks`: Codex only runs hooks you've trusted.
3. `adapters/codex/Containerfile`, the Codex layer. Its launcher is a Node script, so it brings the
   factory's Node the same way the Pi layer does. Both copy the same files from the same image, so
   using both harnesses is fine:
   ```dockerfile
   # Codex harness layer: Codex on the factory's own Node. Built FROM the factory base layer by bin/build-worker.
   ARG BASE_IMAGE
   FROM docker.io/library/node:22-bookworm-slim AS node
   FROM ${BASE_IMAGE}
   COPY --from=node /usr/local/bin/node /opt/factory/node/bin/node
   COPY --from=node /usr/local/lib/node_modules/npm /opt/factory/node/lib/node_modules/npm
   RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /opt/factory/node/bin/npm \
    && PATH=/opt/factory/node/bin:$PATH npm install -g @openai/codex@<pinned-version> \
    && printf '#!/bin/sh\nexec /opt/factory/node/bin/node %s "$@"\n' "$(readlink -f /opt/factory/node/bin/codex)" > /usr/local/bin/codex \
    && chmod +x /usr/local/bin/codex
   ```
4. `config/sandbox-env`: `CODEX_API_KEY`, which `codex exec` reads. A ChatGPT sign-in lives in
   `~/.codex/auth.json` on the host. Copying it into the sandbox exposes a long-lived token, so
   prefer an API key for workers.
5. **Codex has its own OS sandbox, and it may not work nested inside Podman or bubblewrap.**
   `bin/sandbox` is the boundary, so turning Codex's sandbox off is acceptable (Module 3 shows how).
6. Try it inside the sandbox:
   `bin/sandbox "$wt" "$rd" -- env CODEX_HOME="$rd/codex" codex --dangerously-bypass-hook-trust`,
   after copying `config.toml` and `hooks.json` into `$rd/codex`.

**Antigravity (`agy`):**

1. `adapters/agy/plugin/guard.sh`, a `PreToolUse` hook. `agy` passes camelCase JSON on stdin,
   with the tool in `toolCall.name` and its arguments in `toolCall.args`. **It blocks through a
   JSON decision on stdout, not through an exit code**, so this wrapper converts the guard's
   result:
   ```bash
   #!/usr/bin/env bash
   # PreToolUse hook: JSON on stdin → neutral guard → {"decision":"deny"} on stdout to block.
   in=$(cat)
   case "$(jq -r .toolCall.name <<<"$in")" in
     run_command) g=bash.sh;  arg=$(jq -r '.toolCall.args.CommandLine // ""' <<<"$in") ;;
     write_to_file|replace_file_content|multi_replace_file_content)
                  g=files.sh; arg=$(jq -r '.toolCall.args.TargetFile // ""' <<<"$in") ;;
     *) exit 0 ;;
   esac
   if reason=$("$FACTORY_HOME/guards/$g" "$arg" 2>&1 >/dev/null); then
     echo '{"decision": "ask"}'             # guard has no objection: defer to agy's normal permissions
   else
     jq -nc --arg r "${reason:-Blocked by factory guard $g}" '{decision: "deny", reason: $r}'
   fi
   exit 0
   ```
   `decision` is a required output field. When the guard allows, the wrapper answers `ask`, which
   hands the call back to the normal permission rules. It doesn't answer `allow`, which "automatically
   allows the tool execution" and could get around a read-only role's deny list (Module 3). The
   wrapper also **fails closed**: if a guard crashes with any non-zero exit, the call is denied.
   That's the opposite of the exit-code harnesses.
2. `adapters/agy/plugin/hooks.json` registers it:
   ```json
   {
     "factory-guards": {
       "PreToolUse": [
         { "matcher": "run_command|write_to_file|replace_file_content|multi_replace_file_content",
           "hooks": [{ "type": "command", "command": "$FACTORY_HOME/adapters/agy/plugin/guard.sh", "timeout": 10 }] }
       ]
     }
   }
   ```
3. `adapters/agy/Containerfile`, the Antigravity layer. The installer writes to `~/.local/bin` of
   the build user (root), so the layer moves the binary onto the system `PATH`:
   ```dockerfile
   # Antigravity harness layer. Built FROM the factory base layer by bin/build-worker.
   ARG BASE_IMAGE
   FROM ${BASE_IMAGE}
   RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --skip-path --skip-aliases \
    && mv /root/.local/bin/agy /usr/local/bin/agy
   ENV AGY_CLI_DISABLE_AUTO_UPDATE=true
   ```
   The installer has no version option, so the image's version is whatever was current when you
   built it. Rebuild on purpose, not by accident. `agy` has a background self-updater, so turn it
   off (`AGY_CLI_DISABLE_AUTO_UPDATE`). It couldn't write to a read-only binary inside the sandbox
   anyway.
4. Authentication: headless runs normally reuse the sign-in stored in the OS keyring, and there's
   no keyring inside the sandbox. Workers therefore use a Gemini API key, which needs **two**
   things:
   - `GEMINI_API_KEY` in `config/sandbox-env`. `agy` reads only this variable, never
     `GOOGLE_API_KEY` or `.env` files.
   - `"modelProvider": "gemini"` in the run's `settings.json` (Module 3). On its own,
     `GEMINI_API_KEY` has no effect.
5. For `SANDBOX=bwrap`, add `~/.local/bin` to `SANDBOX_RO_PATHS`.
6. Leave `agy`'s own terminal sandbox off (`enableTerminalSandbox` is `false` by default, and
   `--sandbox` is off unless passed). On Linux it uses nsjail, which is unlikely to work nested
   inside Podman or bubblewrap, and `bin/sandbox` is the boundary.
7. **Test this.** The docs don't say whether:
   - a hook's `deny` still blocks under `--dangerously-skip-permissions`. The factory needs this.
   - an `ask` from the hook is approved under `--dangerously-skip-permissions`. If it's
     soft-denied instead, every allowed call fails.
   - hooks in a worktree's `.agents/hooks.json` run without approval. A worktree can also bring
     its own plugins in `.agents/plugins/`. That's why `guards/files.sh` blocks `.agents/`.
   - a hook's exit code matters at all. The wrapper always exits `0`, so it doesn't rely on it.
8. Try it inside the sandbox. The docs list no variable for moving `agy`'s config folder, so give
   it a throwaway `HOME` with the API-key setting and the plugin installed:
   ```bash
   h="$rd/agy"; mkdir -p "$h/.gemini/antigravity-cli"
   cp "$FACTORY_HOME/adapters/agy/settings.full.json" "$h/.gemini/antigravity-cli/settings.json"
   cp -rL "$FACTORY_HOME/adapters/agy/plugin" "$h/factory-plugin"      # resolves the skills symlink
   bin/sandbox "$wt" "$rd" -- env HOME="$h" agy plugin install "$h/factory-plugin"
   bin/sandbox "$wt" "$rd" -- env HOME="$h" agy --dangerously-skip-permissions
   ```
   Inside the session, `/hooks` should list `factory-guards` (`agy plugin enable factory` if it's
   disabled).

### Why guards fail silently (in any harness)

| Symptom | Usual cause |
|---|---|
| Guard never fires | The extension or hook loads at session start, so restart. Pi: the extension isn't passed with `-e`. Claude Code: the plugin isn't loaded (`/hooks` shows nothing) or the matcher doesn't match the tool name. Codex: the hook isn't trusted, or `CODEX_HOME` doesn't contain `hooks.json`. Antigravity: the plugin isn't installed or enabled in the `HOME` the run uses (check `/hooks`), or the hook entry has `"enabled": false` |
| Fires but doesn't block | The guard returns the wrong thing. Pi: return `{ block: true, reason }`. Claude Code and Codex: the exit code must be exactly `2`, and any other non-zero exit lets the action through. A `jq` error in the wrapper counts as "other". Antigravity: the wrapper must print `{"decision": "deny", …}` on stdout. An exit code alone isn't documented to block, and printing `allow` approves the call outright |
| Edits aren't checked in Codex | Codex edits files with `apply_patch`. The paths are inside the patch text, not in a `path` field |
| Model keeps retrying the same thing | The reason says *what* is blocked but not *what to do instead* |
| Works interactively but not in the sandbox | `FACTORY_HOME` or `PATH` is missing inside the sandbox, or the guards directory isn't mounted |

**Try it:** start each harness *inside* the sandbox, using the command from its steps above, then
ask the agent to `git push`, to edit `.env`, to `curl … | sh`, and to read `~/.ssh`.

**Done when:** the sandbox checks behave as expected on at least two backends, `guards/test.sh`
passes, and for **every harness you use**, the first three attempts are blocked by guards with a
reason the agent follows, and the fourth finds nothing because the sandbox hides it.

---

## Module 3: The runner, model routing and the verify gate

**Goal:** one neutral command runs any role on any harness and model, and nothing counts as
"done" unless `scripts/verify` passes.

### Routing config

`config/routing.json` (replace the placeholders with model IDs your harnesses accept):

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

Each routing entry names a harness, so the rest of the entry uses **that harness's vocabulary**:
model IDs, tool names and the access setting. The adapter only reads the keys it understands.
The neutral keys are `harness`, `model` and `output` (`events` or `text`).

A complete Claude-only routing (for a single Claude subscription) is in `config/routing.claude.json`;
its reviewer can only be a different model of the same family, which catches less than
cross-family review.

The harnesses named here are the ones `bin/build-worker` installs (Module 2). After routing starts
using another harness, rebuild each product's worker image.

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
echo "$(date -Is) $role $(jq -r .model <<<"$cfg") sandbox=${SANDBOX:-docker}" >> "$rundir/calls.log"
exec "$FACTORY_HOME/bin/sandbox" "$workdir" "$rundir" -- \
     "$FACTORY_HOME/adapters/$harness/run.sh" "$cfg" "$role" "$workdir" "$prompt" "$rundir"
```

The harness always runs inside `bin/sandbox`, so every role, model and harness gets the same
isolation. Prompt files have to be inside the worktree or the run directory, because nothing
else is mounted.

### The adapter contract

Every `adapters/<harness>/run.sh` takes the same five arguments (`cfg role workdir prompt rundir`)
and must:

1. Run the agent in `workdir`, with the prompt from the `prompt` file and the role prompt from
   `roles/$role.md`.
2. Load the factory guards and skills explicitly, and ignore any harness config the agent could
   have written into the worktree.
3. Keep its session state under `$rundir` and continue the last session when `CONTINUE` is set.
4. Write `$rundir/$role.out.md` (`output: text`) or append to `$rundir/$role.events.jsonl`
   (`output: events`).
5. Exit non-zero if the harness failed. The runner treats this as a failed attempt, not as a
   verdict.

### Harness-specific steps

**Pi:**

1. Routing entries: `"model": "<provider>/<model>:<thinking>"`, `"tools": "read,grep,find,ls"`.
2. `adapters/pi/run.sh`:

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

**Claude Code:**

1. Routing entries: a model alias or full ID, a separate `effort`, Claude Code tool names, and an
   optional per-run cost cap:
   ```json
   "implementer": { "harness": "claude", "model": "sonnet", "effort": "medium", "budget_usd": 3, "output": "events" },
   "reviewer":    { "harness": "claude", "model": "opus", "effort": "high",
                    "tools": "Read,Grep,Glob", "output": "text" }
   ```
2. `adapters/claude/run.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   cfg=$1; role=$2; workdir=$3; prompt=$4; rundir=$5
   model=$(jq -r .model <<<"$cfg")
   effort=$(jq -r '.effort // "medium"' <<<"$cfg")
   tools=$(jq -r '.tools // "Read,Grep,Glob,Bash,Edit,Write"' <<<"$cfg")
   budget=$(jq -r '.budget_usd // empty' <<<"$cfg")
   output=$(jq -r '.output // "events"' <<<"$cfg")

   export CLAUDE_CONFIG_DIR="$rundir/claude/$role"   # sessions per role (for --continue); no host config
   export DISABLE_AUTOUPDATER=1
   args=(-p --model "$model" --effort "$effort" --tools "$tools"
         --permission-mode bypassPermissions          # bin/sandbox is the boundary; hooks still run
         --setting-sources user                       # ignore .claude/settings*.json in the worktree
         --strict-mcp-config                          # ignore .mcp.json in the worktree
         --plugin-dir "$FACTORY_HOME/adapters/claude/plugin"   # guards + skills, same every run
         --append-system-prompt-file "$FACTORY_HOME/roles/$role.md")
   [ -n "$budget" ] && args+=(--max-budget-usd "$budget")
   [ -n "${CONTINUE:-}" ] && args+=(--continue)

   cd "$workdir"
   if [ "$output" = text ]; then
     claude "${args[@]}" < "$prompt" > "$rundir/$role.out.md"
   else
     claude "${args[@]}" --output-format stream-json --verbose < "$prompt" >> "$rundir/$role.events.jsonl"
   fi
   ```
3. `--tools` limits which tools exist, so a reviewer with `Read,Grep,Glob` can't edit even under
   `bypassPermissions`.
4. `bypassPermissions` refuses to run as root. The sandbox runs as your user (`--user`, plus
   `--userns=keep-id` on Podman), so this only matters if you change that.
5. `--max-budget-usd` gives you the per-run hard budget from `cost-strategy.md` for free.

**Codex:**

1. Routing entries: an OpenAI model ID, a separate `effort`, and a `sandbox` setting instead of a
   tool list (Codex has no per-tool allowlist):
   ```json
   "reviewer": { "harness": "codex", "model": "<openai-model>", "effort": "high",
                 "sandbox": "read-only", "output": "text" }
   ```
2. `adapters/codex/run.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   cfg=$1; role=$2; workdir=$3; prompt=$4; rundir=$5
   model=$(jq -r .model <<<"$cfg")
   effort=$(jq -r '.effort // "medium"' <<<"$cfg")
   sandbox=$(jq -r '.sandbox // "bypass"' <<<"$cfg")   # bypass | read-only | workspace-write
   output=$(jq -r '.output // "events"' <<<"$cfg")

   export CODEX_HOME="$rundir/codex/$role"              # sessions per role; host ~/.codex never used
   mkdir -p "$CODEX_HOME/skills"
   cp "$FACTORY_HOME/adapters/codex/"{config.toml,hooks.json} "$CODEX_HOME/"
   cp -r "$FACTORY_HOME/skills/." "$CODEX_HOME/skills/"  # same skills every run

   args=(-m "$model" -c "model_reasoning_effort=\"$effort\"" -C "$workdir"
         --dangerously-bypass-hook-trust)               # our hooks are vetted and mounted read-only
   if [ "$sandbox" = bypass ]; then args+=(--dangerously-bypass-approvals-and-sandbox)
   else args+=(--sandbox "$sandbox"); fi

   sub=(exec); [ -n "${CONTINUE:-}" ] && sub=(exec resume --last)
   # Codex has no append-system-prompt flag: the role prompt goes first, so it stays a stable prefix
   input() { cat "$FACTORY_HOME/roles/$role.md"; echo; cat "$prompt"; }
   if [ "$output" = text ]; then
     input | codex "${sub[@]}" "${args[@]}" -o "$rundir/$role.out.md" - > "$rundir/$role.log"
   else
     input | codex "${sub[@]}" "${args[@]}" --json - >> "$rundir/$role.events.jsonl"
   fi
   ```
3. Implementers use `bypass`, because `bin/sandbox` is the boundary and Codex's own sandbox may
   not work nested. For read-only roles, try `read-only` first. If it fails inside the
   container, use `bypass` and add a neutral check to `bin/run-task`: after a read-only role runs,
   `git -C "$wt" status --porcelain` must be empty.
4. `--dangerously-bypass-hook-trust` also trusts a `.codex/hooks.json` written into the
   worktree. That's why `guards/files.sh` blocks `.codex/` (Module 2).
5. `codex exec resume` may accept fewer flags than `codex exec`. Check
   `codex exec resume --help` on your version.

**Antigravity (`agy`):**

1. Routing entries: a model slug from `agy models`, an `access` setting instead of a tool list,
   and a `timeout`. Slugs already name an effort level (for example `gemini-3.8-flash-medium`).
   Add `"effort"` (`low`, `medium` or `high`) only to override it, and **test this**: the docs
   don't say which one wins when they disagree.
   ```json
   "scout":    { "harness": "agy", "model": "<flash-slug>", "access": "read-only", "output": "text" },
   "reviewer": { "harness": "agy", "model": "<pro-slug>", "access": "read-only",
                 "timeout": "15m", "output": "text" }
   ```
2. Two settings files select the access level. Both set `modelProvider` for API-key auth
   (Module 2). `agy` has no tool allowlist flag, so read-only is a `deny` list. Deny rules
   override everything else ("Deny > Ask > Allow"), including the default that auto-allows writes
   inside the workspace. `adapters/agy/settings.read-only.json`:
   ```json
   { "modelProvider": "gemini", "enableTelemetry": false,
     "permissions": { "deny": ["write_file(*)", "command(*)", "execute_url(*)", "mcp(*)"] } }
   ```
   `adapters/agy/settings.full.json`: `{ "modelProvider": "gemini", "enableTelemetry": false }`.
   Full-access roles run with `--dangerously-skip-permissions` instead. Reading inside the
   workspace is allowed by default, so the read-only role needs no `allow` rule. Don't add
   `read_file(*)`, which would allow reading every file on the system.
3. `adapters/agy/run.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   cfg=$1; role=$2; workdir=$3; prompt=$4; rundir=$5
   model=$(jq -r .model <<<"$cfg")
   effort=$(jq -r '.effort // empty' <<<"$cfg")
   access=$(jq -r '.access // "full"' <<<"$cfg")       # full | read-only
   timeout=$(jq -r '.timeout // "30m"' <<<"$cfg")      # agy's default of 5m is too short for implementers
   output=$(jq -r '.output // "events"' <<<"$cfg")

   # no documented config-dir variable: each role gets its own HOME (sessions, settings, plugin)
   export HOME="$rundir/agy/$role" AGY_CLI_DISABLE_AUTO_UPDATE=true
   conf="$HOME/.gemini/antigravity-cli"
   if [ ! -f "$conf/settings.json" ]; then
     mkdir -p "$conf"
     cp "$FACTORY_HOME/adapters/agy/settings.$access.json" "$conf/settings.json"
     cp -rL "$FACTORY_HOME/adapters/agy/plugin" "$HOME/factory-plugin"   # -L resolves the skills symlink
     agy plugin install "$HOME/factory-plugin" >&2
   fi

   args=(-p --model "$model" --print-timeout "$timeout")
   [ -n "$effort" ] && args+=(--effort "$effort")
   [ "$access" = full ] && args+=(--dangerously-skip-permissions)   # read-only: the deny list decides
   [ -n "${CONTINUE:-}" ] && args+=(--continue)
   # no append-system-prompt flag: the role prompt goes first, so it stays a stable prefix
   input="$(cat "$FACTORY_HOME/roles/$role.md"; echo; cat "$prompt")"

   cd "$workdir"
   if [ "$output" = text ]; then
     agy "${args[@]}" "$input" > "$rundir/$role.out.md" 2>> "$rundir/$role.agy.log"
     [ -s "$rundir/$role.out.md" ] || { echo "agy: empty output" >&2; exit 1; }
   else
     agy "${args[@]}" --output-format stream-json "$input" \
       >> "$rundir/$role.events.jsonl" 2>> "$rundir/$role.agy.log"
   fi
   ```
4. `agy -p` exits non-zero when a run fails to produce a response (unknown model: exit `1`, status
   `ERROR`). That already meets contract rule 5.
5. **Permission refusals don't fail the run.** In headless mode, a call that needs approval it
   can't get is *soft-denied*: the run continues, exits `0`, and prints a notice to stderr.
   That's why stderr goes to `$role.agy.log`. If a read-only role's output looks thin, check
   that log for the calls it was refused.
6. The empty-output check exists because early versions printed nothing when stdout wasn't a
   terminal (`google-antigravity/antigravity-cli` issue #76). Run `agy -p "say hi" > out.txt` on
   your version before trusting it.
7. In `-p` mode, an unknown `--model` slug fails the run rather than falling back silently,
   which is what you want. Pin slugs exactly as `agy models` prints them.

### `bin/run-task`: implement one task, gated by verify

```bash
#!/usr/bin/env bash
# usage: run-task <worktree> <task-file> <run-dir>   (task-file: a path inside the worktree)
set -euo pipefail
export LC_ALL=C                                 # sort and diff must agree on the order
FACTORY_HOME="$(cd "$(dirname "$0")/.." && pwd)"; export FACTORY_HOME
wt=$1; task=$2; rundir=$3; mkdir -p "$rundir"
run() { "$FACTORY_HOME/bin/agent-run" "$@"; }
verify() { "$FACTORY_HOME/bin/sandbox" --net none "$wt" "$rundir" -- scripts/verify > "$rundir/verify.log" 2>&1; }
deps() { "$FACTORY_HOME/bin/sandbox" --net none "$wt" "$rundir" -- bash "$rundir/deps.sh" 2>"$rundir/deps.log" | sort -u; }

# dependency gate (skipped if the product has no scripts/deps): main's copy of the script, so the
# task can't change how dependencies are listed. deps_changed is true when the task changed them.
gate=0
if git -C "$wt" show main:scripts/deps > "$rundir/deps.sh" 2>/dev/null && deps > "$rundir/deps.before"; then gate=1; fi
deps_changed() {
  [ $gate = 1 ] || return 1
  deps > "$rundir/deps.after" || { echo "scripts/deps failed, see deps.log" > "$rundir/deps.diff"; return 0; }
  ! diff "$rundir/deps.before" "$rundir/deps.after" > "$rundir/deps.diff"
}

{ printf 'Complete the task in %s. Write REPORT.md as it specifies.\n' "$task"
  printf 'Do not add, remove or upgrade dependencies: everything this task needs is already declared on main and in the image. If you need a change, stop and explain which one and why under open questions in REPORT.md.\n'
} > "$rundir/brief.md"
run implementer "$wt" "$rundir/brief.md" "$rundir" || true

status=red
if deps_changed; then status=deps-changed                     # stop before any fix round
else
  for role in implementer implementer implementer-strong; do    # 2 fix rounds, then escalate
    if verify; then status=green; break; fi
    { cat "$rundir/brief.md"                                     # implementer-strong starts a new session
      echo "scripts/verify failed. Fix the cause (don't weaken the tests). Output:"; tail -60 "$rundir/verify.log"; } > "$rundir/fix.md"
    if [ "$role" = implementer ]; then CONTINUE=1 run "$role" "$wt" "$rundir/fix.md" "$rundir" || true
    else run "$role" "$wt" "$rundir/fix.md" "$rundir" || true; fi
  done
  [ $status = red ] && verify && status=green
  deps_changed && status=deps-changed
fi
echo "$status" > "$rundir/status"
```

The gate is outside the harness, so it works the same with any model. The model can't declare
itself done. Only `scripts/verify` decides.

**Tasks never change dependencies.** Adding, removing or upgrading one is decided while planning,
approved by you, and lands on `main` before the tasks that need it run (Module 4). `bin/fan-out`
rebuilds the worker image from `main` first, so the image already holds everything a task needs.
The implementer has network only because the harness needs it to reach the model.

Two things enforce the rule:

- **verify, offline.** A dependency the image doesn't have can't be resolved, and nothing an agent
  downloads survives into verify, because every sandbox call is a new container. This covers
  build tools that download outside the worktree (Gradle, Maven, sbt, Cargo, Go).
- **the dependency gate.** npm and pip into a venv install into the worktree, so verify would
  pass. The runner runs `main`'s `scripts/deps` before the implementer, right after its first
  call, and again at the end. Any difference sets the status to `deps-changed`: the task is neither
  committed nor reviewed, and `deps.diff` shows what changed. For the other build tools the gate
  turns a resolution error into the same clear status, before any fix round is spent on it.

The fix rounds repeat the brief: `implementer-strong` starts a new session and would otherwise
see only the verify output, not the task or the dependency rule.

**Try it:** give one small task to `run-task` on a fresh worktree. Then break the task on purpose
(ask for something the tests will reject) and watch the fix rounds and the escalation happen.

**Done when:** you switch the implementer to another provider by editing only `routing.json`,
and the same task still goes green. Once a second adapter exists, do the same for the
**harness**: change only `"harness"` (and its model ID and harness-specific keys) and the task
still goes green.

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
  It lists the dependency changes the spec needs (see below).

**Dependency changes are a planning decision, and they land on `main` first.** Tasks never add,
remove or upgrade a dependency (Module 3). The `plan` skill works out the changes the whole spec
needs and writes them to `docs/specs/NNN-name/dependencies.md`: for each one, the exact name and
version, which tasks need it, and why. It prefers what the product already uses. Then:

1. You review the list with the task files. That's the human decision, made once and cheaply,
   before any agent runs.
2. The approved changes land on `main` as their own commit, touching only build files and
   lockfiles. You make it, or the lead session drafts it on your instruction for you to commit.
   Use the package manager's own command where there is one, so the lockfile is right.
3. `bin/fan-out` rebuilds the worker image from `main` before the batch (Module 6), so the image
   pre-fetches the new dependencies. To check the commit on its own first, run
   `bin/build-worker` and `bin/check-product --run`.
4. The tasks run against an image that already has everything.

A dependency then gets a review of its own instead of hiding inside a feature diff, its code is
first downloaded by the image build on the host (no agent session, no API keys), and parallel
tasks never edit the same manifest and lockfile. If the planner missed one, the implementer stops
and says so in `REPORT.md` (status `red`), or the runner stops it (`deps-changed`). The
orchestrator brings it to you (Module 7).

Run both interactively with the planner's model, in any harness.

### Harness-specific steps

**Pi:**

1. `pi --model <planner-model>`. The skills come from the installed package (Module 0).
2. Invoke them by name: *"use the spec skill"*.

**Claude Code:**

1. `claude-factory --model opus --effort high` (the alias from Module 0).
2. Invoke them as `/factory:spec` and `/factory:plan`.
3. When the plan skill calls `bin/agent-run scout`, Claude Code asks for permission to run it.
   Allow it once for the session, or add `Bash(~/factory-model/bin/agent-run:*)` to your user
   settings' allow list.

**Codex:**

1. `codex -m <planner-model> -c 'model_reasoning_effort="high"'`. The skills come from
   `~/.codex/skills` (Module 0).
2. Invoke them by name, or pick them from `/skills`.

**Antigravity (`agy`):**

1. `agy --model <planner-slug>`. The skills come from the installed plugin (Module 0).
2. Every skill becomes a slash command named after the skill: `/spec`, `/plan`. The agent may
   also pick a skill by itself from its description.
3. To let the plan skill call the scout without asking every time, add
   `"command(/home/<you>/factory-model/bin/agent-run)"` to `permissions.allow` in
   `~/.gemini/antigravity-cli/settings.json`.

Skill text stays neutral. Write *"run `$FACTORY_HOME/bin/agent-run scout …`"*, not *"use the
Task tool"* or another harness's built-in tool.

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
read-only access is enforced by `routing.json`, not by asking nicely. The reviewer role also
flags any change to build files or lockfiles: tasks don't change dependencies, and the gate only
sees direct dependencies, not build plugins or other build settings.

The easiest way to get a different family is a different **harness**: implementer on Claude
Code, reviewer on Codex, or the other way round. Pi can serve either side.

### Harness-specific steps

**Pi:**

1. Reviewer entry: `"tools": "read,grep,find,ls"`, `"output": "text"`.

**Claude Code:**

1. Reviewer entry: `"tools": "Read,Grep,Glob"`, `"output": "text"`. No `Bash`, so it can't run
   anything.
2. Optional: `--json-schema` can force a structured verdict, but keep the `VERDICT:` first line
   so `run-task` stays neutral.

**Codex:**

1. Reviewer entry: `"sandbox": "read-only"`, `"output": "text"`. The `-o` flag writes only the
   final message to `reviewer.out.md`, so the `VERDICT:` line is the file's first line.
2. Codex can still run read-only shell commands in this mode. That's acceptable for a reviewer,
   and the porcelain check from Module 3 catches any writes.

**Antigravity (`agy`):**

1. Reviewer entry: `"access": "read-only"`, `"output": "text"`. In text mode `agy -p` prints only
   the final response, so the `VERDICT:` line is the file's first line.
2. With a Gemini slug, this is a third family. With a Claude implementer, a Codex reviewer and an
   `agy` reviewer you can run Module 5's comparison across three families. On an account plan
   `agy` also offers Claude models. Don't pick one for the reviewer when the implementer is Claude.
3. Optional: `--json-schema` can force a structured verdict, but keep the `VERDICT:` first line
   so `run-task` stays neutral.

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
RUN="$FACTORY_HOME/runs/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$RUN"
case "${SANDBOX:-docker}" in                     # keep the worker image in step with main
  podman|docker) "$FACTORY_HOME/bin/build-worker" "$PRODUCT" > "$RUN/build-worker.log" 2>&1 \
                   || { echo "build-worker failed, see $RUN/build-worker.log" >&2; exit 1; } ;;
esac
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

**Build** `bin/collect`: for each task in a run, print the id, the status (`green`, `red` or
`deps-changed`), the review verdict, the `REPORT.md` summary and open questions, the diff stat,
`deps.diff` for `deps-changed`, and the models used (from `calls.log`). This is your dashboard.

Rules:
- Only run tasks together if their `touches` don't overlap and they don't depend on each other.
- Nothing is pushed or merged by agents. The runner commits to local branches, and you merge.

### Harness-specific steps

All three adapters keep their session state under `$rundir`, so parallel workers never share
sessions. What differs is how much parallelism your account can take.

**Pi:**

1. Limits are per provider. Check each provider's rate limits before raising the batch size.

**Claude Code:**

1. With `CLAUDE_CODE_OAUTH_TOKEN`, all workers share one subscription quota. Parallel workers use
   it up quickly, so keep batches small, or route bulk roles to the API key.
2. `bin/collect` can read each worker's cost from the `result` event at the end of
   `implementer.events.jsonl` (`total_cost_usd`).

**Codex:**

1. With an API key, limits are per OpenAI organisation tier. With a ChatGPT plan, all workers
   share its quota.
2. Each worker has its own `CODEX_HOME`, so `resume --last` always finds the right session.

**Antigravity (`agy`):**

1. Workers use `GEMINI_API_KEY`, so the Gemini API rate limits of that key's project apply.
   Check your tier in Google AI Studio before raising the batch size. Interactive sessions on an
   account plan have separate five-hour and weekly limits (`/usage` shows them).
2. Each worker has its own `HOME` under its run directory, so `--continue` always finds the
   right conversation.
3. Set `timeout` in routing high enough for your slowest task. **Test this:** the docs don't say
   which status a run that hits `--print-timeout` ends with. Check that it exits non-zero, so
   `run-task` counts it as a failed attempt.

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
   files, and re-queues failures. When a task needs a dependency change (`deps-changed`, or a
   request in `REPORT.md`), it either rewrites the task so the change isn't needed, or brings it
   to you. Once you approve it, the change lands on `main` (Module 4) and the task is re-queued.
4. Shows **you** only: branches ready to merge, questions that need you, and escalations.
5. **Human gate:** it never merges. You merge, then clean up with `git worktree remove` and
   delete the branch.

The same flow runs in any harness that can read a skill and run bash, so the orchestrator
isn't tied to Pi either.

### Harness-specific steps

The orchestrator runs **on the host**, interactively. It isn't sandboxed, so the harness's own
approvals and your guards are what protect you here.

**Pi:**

1. `pi --model <planner-model>`, then *"use the orchestrate skill on docs/specs/NNN-name"*.
2. Pi doesn't ask before running commands, so the factory guards (installed globally in Module 0)
   are the only check.

**Claude Code:**

1. `claude-factory --model opus`, then `/factory:orchestrate docs/specs/NNN-name`.
2. Allow the factory scripts once, so it doesn't stop at every batch: add
   `Bash(~/factory-model/bin/*)` to the allow list in your user settings. Leave everything else
   on the default mode, which asks first.

**Codex:**

1. `codex -m <planner-model>`, then pick `orchestrate` from `/skills`.
2. Codex's default sandbox may block `bin/fan-out` (it creates worktrees outside the product
   repo and starts containers). Run the orchestrator with `--sandbox danger-full-access` and
   approvals on, or allow `~/projects/<product>-wt` as a writable root.

**Antigravity (`agy`):**

1. `agy --model <planner-slug>`, then `/orchestrate docs/specs/NNN-name`.
2. Allow the factory scripts once, by adding each script's full path to `permissions.allow` in
   `~/.gemini/antigravity-cli/settings.json`, for example
   `"command(/home/<you>/factory-model/bin/fan-out)"` and `"command(/home/<you>/factory-model/bin/collect)"`.
   Rules match whole words from the start of the command, so a folder prefix like `…/bin/`
   doesn't cover the scripts in it. Leave `toolPermission` on its default, `request-review`,
   for everything else.
3. If you turned on `agy`'s terminal sandbox (`enableTerminalSandbox`, off by default), it
   blocks `bin/fan-out`, which writes outside the product and starts containers. Run the
   orchestrator with the sandbox off, or allow those scripts to run outside it with an
   `unsandboxed(…)` rule.

### 7b. The factory log

`docs/factory-log.md`: one line for each time something went wrong. **Include the harness and
the model**, because failures often depend on them:

```
2026-10-03 | 012-csv-export | implementer=claude/<model> | edited unrelated files | cause: task Context too vague | fix: plan skill now requires explicit `touches`
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
| A harness ignored a guard, flag or config | that harness's adapter (`adapters/<name>/`) |

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
- Metrics per **role × harness × model**: pass rate, fix rounds, escalation rate, review
  findings, cost, and wall time.
- `bin/metrics`: one small parser per harness turns `*.events.jsonl` into the same row
  (tokens in/out/cached, cost, turns, duration). The parsers are the only harness-specific part.

### Harness-specific steps

**Pi:**

1. Parse Pi's JSON event stream (`--mode json`) for usage and cost per run.

**Claude Code:**

1. The last line of each `stream-json` run is a `result` event with `total_cost_usd`, `usage`,
   `num_turns` and `duration_ms`. It's ready to use.
2. On a subscription the cost is notional. Track quota usage separately.

**Codex:**

1. `--json` events report token usage per turn, not cost. Compute the cost from token counts
   and a price table in `config/`.

**Antigravity (`agy`):**

1. The `result` event in `stream-json` carries `usage` (`input_tokens`, `output_tokens`,
   `thinking_tokens`, `cache_read_tokens`, `total_tokens`), `num_turns` and `duration_seconds`.
   It has no cost, so price it from the same table as Codex.
2. In a streaming session, `usage`, `num_turns` and `duration_seconds` are **cumulative** for
   the session. **Test this** for `--continue` runs: if `num_turns` is above 1 in a fix round,
   the counters cover the whole conversation. In that case, take the difference from the
   previous `result` event, or fix rounds will be counted twice.

**Try it:** run the evals with two implementer models, or with the same model on two harnesses.
Keep whichever wins on cost per passed task.

**Done when:** a change to `routing.json` or a role prompt is backed by eval numbers.

---

## Order and pacing

| Module | What you gain |
|---|---|
| 0–1 | The neutral factory, its adapters, and an agent-ready product |
| 2 | Isolation and guards that work with any harness |
| 3 | **One runner, any model, done means verified (the foundation)** |
| 4–5 | Repeatable work orders and cross-model review |
| 6 | Real parallelism without chatting to each agent |
| 7 | An orchestrator, and a factory that improves itself |
| 8 | Model routing and factory changes decided by data |

Adding another harness later means following the "harness-specific steps" of each module for it:
an `adapters/<name>/Containerfile`, a guard wrapper, `adapters/<name>/run.sh` that meets the adapter contract, and
a metrics parser. Nothing in the neutral core changes.
