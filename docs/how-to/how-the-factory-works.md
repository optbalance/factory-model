# How the factory works

The big picture in diagrams: which directories exist, where things run, and what happens between
"here's a story" and "it's merged". The build steps are in `building-the-factory.md`.

---

## 1. Three directories

```
~/factory-model/                 THE FACTORY: how work is done (this repo)
├── bin/                         scripts: start, sandbox, build-worker, agent-run, run-task, fan-out, collect
├── config/                      routing.json (role → harness + model), sandbox-env (allowed env vars)
├── roles/ skills/ guards/       role prompts, skills, guard scripts
├── sandbox/Containerfile        factory base layer of the worker image
├── adapters/<harness>/          everything harness-specific, incl. that harness's image layer
└── runs/<run>/<task>/           logs of each run: briefs, calls.log, verify.log, status, review

~/projects/<product>/            THE PRODUCT: what is being built (its own repo)
├── AGENTS.md                    product knowledge for agents
├── scripts/verify               the one health check (exit 0 = healthy)
├── toolchain.Containerfile      the image the product builds and tests in
├── docs/specs/                  specs and task files
└── .git/                        the product's history, shared by all of its worktrees

~/projects/<product>-wt/         THE WORKTREES: one checkout per task in progress
├── 012-csv-export/              branch factory/012-csv-export
└── 013-date-filter/             branch factory/013-date-filter
```

**The worktrees directory** is the one that's easy to forget. A *git worktree* is an extra
working copy of the same repo, checked out on its own branch. All worktrees share the product's
`.git`, so they cost almost nothing and every commit lands in the product's history. The factory
creates one worktree per task, so several agents can work in parallel without touching each
other's files or your own checkout in `~/projects/<product>/`. The worktrees sit *outside* the
product repo so they never appear inside it. Each one is deleted after you merge its branch.

| | Factory | Product | Worktrees |
|---|---|---|---|
| Is | A git repo | A git repo | Extra checkouts of the product repo |
| Holds | Process knowledge, same for every product | Domain knowledge, code, tests | One task's branch |
| Changed by | You (factory improvements) | You (merging) | Agents (inside the sandbox) |
| Lives | For good | For good | Until the task is merged |

**The contract between factory and product** is the only thing the factory knows about a product:
`AGENTS.md`, `scripts/verify`, `docs/specs/` and `toolchain.Containerfile` (holding every
dependency `main` declares).

---

## 2. Hosts and sandboxes

Everything runs on one machine. You, the orchestrator and the factory scripts run on the host.
Each agent call and each verify run gets its own short-lived sandbox (a container that is
removed when the command ends). Only the worktree and the run directory carry over from one call
to the next.

```mermaid
flowchart TB
  subgraph HOST["Host machine (your user)"]
    YOU["You"]
    ORCH["Orchestrator session<br/>(interactive harness + orchestrate skill)"]
    SCRIPTS["bin/fan-out, bin/run-task, bin/collect<br/>git worktree add, git commit"]
    FDIR[("~/factory-model")]
    PDIR[("~/projects/&lt;product&gt;")]
    WDIR[("~/projects/&lt;product&gt;-wt/&lt;task&gt;")]
    YOU <--> ORCH
    ORCH --> SCRIPTS
  end

  subgraph SBX1["Sandbox: agent call (network open)"]
    AGENT["Harness: Pi / Claude Code / ...<br/>role: implementer, reviewer, ..."]
  end
  subgraph SBX2["Sandbox: verify (no network)"]
    VERIFY["scripts/verify"]
  end

  SCRIPTS -- "bin/agent-run → bin/sandbox" --> SBX1
  SCRIPTS -- "bin/sandbox --net none" --> SBX2
  FDIR -. "read-only" .-> SBX1
  FDIR -. "read-only" .-> SBX2
  WDIR -. "read-write" .-> SBX1
  WDIR -. "read-write" .-> SBX2
  PDIR -. ".git read-only" .-> SBX1
  AGENT -- "provider API" --> LLM(["LLM providers"])
```

What a sandbox can and can't reach:

| Mounted | Access | Not there at all |
|---|---|---|
| `~/factory-model` | read-only, so agents can't change their own guards, roles or routing | your home directory, SSH keys |
| the task's worktree | read-write, the only code the agent may change | cloud and push credentials |
| the task's run directory (`runs/<run>/<task>/`) | read-write | other repos and other worktrees |
| the product's shared `.git` | read-only, so `git diff` works but history can't be rewritten | env vars not listed in `config/sandbox-env` |

### The worker image

With the container backends (`SANDBOX=docker`, the default, or `podman`), every sandbox for a product starts
from that product's worker image. `bin/build-worker` builds it once per product, layer by layer,
each built `FROM` the one below:

```mermaid
flowchart BT
  T["toolchain<br/>product's toolchain.Containerfile<br/>OS + JDK/Gradle, Node, ..."]
  B["base<br/>factory's sandbox/Containerfile<br/>git, jq, curl"]
  H1["pi<br/>adapters/pi/Containerfile"]
  H2["claude<br/>adapters/claude/Containerfile"]
  T --> B --> H1 --> H2
  H2 -. "tagged :latest" .-> IMG(["factory-worker-&lt;product&gt;"])
```

The product is at the bottom because it brings the OS. Only the harnesses `config/routing.json`
uses are included. The factory's code isn't in the image: it's mounted read-only at run time, so
changing a guard or a role needs no rebuild. With `SANDBOX=bwrap` there's no image, and the
host's own `/usr` provides the toolchain and the harnesses.

---

## 3. From story to merge

### Once per product: plug it in

```mermaid
flowchart LR
  A["Product meets the contract<br/>(AGENTS.md, scripts/verify,<br/>docs/specs/, toolchain.Containerfile)"]
  --> B["bin/check-product &lt;product&gt;"]
  --> C["bin/build-worker &lt;product&gt;"]
  --> D["bin/check-product --run &lt;product&gt;<br/>(verify passes, sandboxed, offline)"]
```

### Every story

```mermaid
sequenceDiagram
  autonumber
  actor You
  participant Orch as Lead session (host)<br/>spec, plan, orchestrate skills
  participant Prod as Product repo<br/>(main)
  participant Run as fan-out + run-task<br/>(host)
  participant WT as Worktree<br/>(one per task)
  participant Impl as Implementer<br/>(sandbox)
  participant Ver as scripts/verify<br/>(sandbox, offline)
  participant Rev as Reviewer<br/>(sandbox, other model family)

  You->>Orch: story / feature idea
  Orch->>You: spec skill: interview (goal, users, constraints, edge cases)
  Orch->>Prod: docs/specs/NNN-name.md
  Orch->>Prod: plan skill: task files in docs/specs/NNN-name/tasks/ + dependencies.md
  You->>Prod: review and commit spec + tasks on main
  You->>Prod: commit the approved dependency changes on main (build files, lockfiles)
  Orch->>Orch: batch tasks by depends_on and touches
  Orch->>Run: bin/fan-out <product> <tasks of one batch>
  Run->>Run: bin/build-worker: image from main, with every dependency pre-fetched
  par each task in the batch, in parallel
    Run->>WT: git worktree add -b factory/<id> (from main)
    Run->>Impl: brief: "complete the task, write REPORT.md"
    Impl->>WT: edits code, runs builds and tests
    loop up to 2 fix rounds, then escalate to implementer-strong
      Run->>Ver: run verify
      Ver-->>Run: red + output
      Run->>Impl: "verify failed, fix the cause"
    end
    Run->>Ver: run verify
    Ver-->>Run: green
    Run->>WT: git commit on factory/<id>
    Run->>Rev: task file + diff
    Rev-->>Run: VERDICT: approve / changes-needed
  end
  Run-->>Orch: runs/<run>/<id>/: status, verdict, REPORT.md
  Orch->>Orch: bin/collect, triage: answer questions, rewrite tasks, re-queue failures
  Orch->>You: branches ready to merge, open questions, escalations
  You->>Prod: merge factory/<id> into main
  You->>WT: git worktree remove, delete the branch
  You->>Orch: failures → docs/factory-log.md → retro → factory improvements
```

Steps 1–6 are interactive and happen once per story. Steps 7 and later repeat for each batch of
tasks until the story's tasks are merged. Three rules hold for every task:

- **Dependencies change on `main`, never in a task.** The planner lists the dependency changes a
  spec needs, you approve them and commit them on `main` before the tasks run, and the worker
  image is rebuilt with them. Offline verify stops a task that changes them anyway where the
  build tool downloads outside the worktree; elsewhere the reviewer sees the change in the diff.
- **Done means verified.** Only `scripts/verify` decides a task is green, checked by the runner
  after the agent exits. The model can't declare itself done.
- **You merge.** Agents never push or merge. The runner commits to local `factory/<id>`
  branches, and you decide what reaches `main`.

### Inside one task (`bin/run-task`)

```mermaid
flowchart TD
  S(["task file in the worktree"]) --> I["implementer: do the task<br/>(sandbox, network open)"]
  I --> V{"verify<br/>(sandbox, no network)"}
  V -- green --> C["runner commits on factory/&lt;id&gt;"]
  V -- "red, round 1-2" --> F["implementer continues:<br/>fix the cause"] --> V
  V -- "red, round 3" --> E["implementer-strong:<br/>fix the cause"] --> V2{"verify"}
  V2 -- green --> C
  V2 -- red --> R(["status: red<br/>orchestrator triages"])
  C --> RV["reviewer: diff vs acceptance criteria<br/>(sandbox, read-only tools)"]
  RV --> D(["status: green + verdict<br/>ready for you"])
```

Every box that says *sandbox* is a separate, fresh container. Nothing carries over between them
except what's in the worktree and the run directory.

---

## 4. Where things end up

| Artifact | Where | Kept |
|---|---|---|
| Spec, task files | product: `docs/specs/` | yes, on `main` |
| Code changes, `REPORT.md` | worktree, branch `factory/<id>` | merged by you, or dropped |
| Briefs, `calls.log`, `verify.log`, `status`, `diff.patch`, review | factory: `runs/<run>/<id>/` | gitignored, local history |
| Approved dependency changes | product: build files and lockfiles, plus `docs/specs/NNN-name/dependencies.md` | yes, on `main` |
| Failures and their fixes | factory: `docs/factory-log.md` | yes, drives factory improvements |
| Product knowledge learned | product: `AGENTS.md` | yes |
| Process knowledge learned | factory: skills, roles, guards, routing | yes |
