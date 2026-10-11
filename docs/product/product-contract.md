# Product contract

What a product repo must provide before the factory can develop it. Work through the steps in
order; each one says what to add, why the factory needs it, and which file in
`factory-model/templates/` to start from. Templates are starting points: copy, then adapt them
to the product. Everything here lives in the **product** repo.

| Step | Product file | Template | Required |
|---|---|---|---|
| 1 | git repo with a `main` branch | — | always |
| 2 | `AGENTS.md` | `templates/AGENTS.md` | always |
| 3 | `CLAUDE.md` → `AGENTS.md` symlink | — | if any role runs on Claude Code |
| 4 | `scripts/verify` | `templates/verify` | always |
| 5 | `docs/specs/` | — | always |
| 6 | `toolchain.Containerfile` | `templates/toolchain.Containerfile` | with `SANDBOX=docker` (default) or `podman` |
| 7 | `factory.dep-cache` label in the image | `templates/toolchain.Containerfile` | if the build tool downloads dependencies outside the worktree |
| 8 | `scripts/deps` | `templates/deps` | recommended |
| 9 | Commit on `main` and check | — | always |

---

## Step 1. A git repo with a `main` branch

**What:** the product is a git repository with a branch named `main`.

**Why:** every task runs in its own git worktree created from `main`, and the worker image is
built from `main`. Uncommitted or unmerged work is invisible to the factory.

**Template:** none.

## Step 2. `AGENTS.md` at the repo root

**What:** the context file every agent reads first. It contains:

- one sentence on what the product does;
- architecture in about 10 lines: main parts, how data or requests flow, where state lives,
  external services;
- layout: where code, tests, scripts and specs live;
- commands: how to build, run and test;
- definition of done: work is done only when `scripts/verify` exits 0; tests are never weakened,
  skipped or deleted to make it pass;
- conventions the linter doesn't enforce;
- "never touch" areas: generated code, applied migrations, public contracts;
- links to deeper docs instead of their content.

Keep it under about 150 lines and write it for any model, with no provider-specific tricks.
Don't tell agents to commit, push, merge, switch branches or ask the user before acting. In the
factory nobody is there to answer, and the runner commits after verify passes. Open questions go
in the task's `REPORT.md`.

**Why:** agents start cold, with no memory of earlier tasks. This file is the only product
knowledge they get for free, so it decides how well they work.

**Template:** `templates/AGENTS.md`. Delete sections that don't apply rather than leaving them empty.

## Step 3. `CLAUDE.md` symlink (only if Claude Code is used)

**What:** `ln -s AGENTS.md CLAUDE.md`, committed as a symlink.

**Why:** Claude Code reads `CLAUDE.md`, not `AGENTS.md`. A symlink keeps one source of truth;
a copy would drift.

**Template:** none.

## Step 4. `scripts/verify`

**What:** one executable script that exits `0` when the product is healthy and non-zero when it
isn't: build, lint, type checks, tests. It must:

- be committed with the executable bit (`chmod +x scripts/verify && git add scripts/verify`);
- run without prompts, colors or watch mode;
- run **offline**: no network, no database or other external service, nothing from your home
  directory, no uncommitted or gitignored files (`.env`). Tests that need any of these don't
  belong in verify;
- be quiet on success and specific on failure: the failing step, the command and the end of its
  output. Agents fix problems from this output alone;
- stay fast. Aim for under 2 minutes; over that, add a `--quick` mode;
- if dependencies live in the worktree (`node_modules`, a venv), fail with a one-line message that
  names the install command when they're missing.

**Why:** it's the factory's only definition of "done". The runner runs it after the agent exits,
in a fresh sandbox without network; the agent can't declare a task finished.

**Template:** `templates/verify`. Replace the `step` lines with your stack's commands.

## Step 5. `docs/specs/`

**What:** a committed `docs/specs/` directory. If it's empty, add `docs/specs/.gitkeep`, because
git doesn't track empty directories.

**Why:** specs and task files, the factory's work orders, are written here and committed on `main`
so every worktree has its own copy.

**Template:** none.

## Step 6. `toolchain.Containerfile`

**What:** the image that verify and the agents' build and test commands run in. The factory
builds it from `main` with the repo root as build context, and adds its own layers on top. It
must be:

- **Debian- or Ubuntu-based.** Alpine doesn't work.
- **Usable by any user.** Commands run as your user ID with `HOME=/tmp`. Install tools system-wide
  (`/usr/local`, `/opt`), never under `/root` or `~`.
- **Using fixed cache paths.** Point every tool cache at a fixed path with `ENV`, and make it
  writable by any user (`chmod -R a+rwX`). JVM tools take `~` from `/etc/passwd`, not `$HOME`, and
  the sandbox user usually has no entry there.
- **Complete offline for `main`.** The toolchain, the build tool's own distribution (for example
  the Gradle wrapper's) and every dependency `main` declares are in the image. To pre-fetch, `COPY`
  only the build files (not the sources), so a source change doesn't trigger a re-download.
- **Free of `ENTRYPOINT` requirements.** The factory clears it and runs commands directly.

If the product already has a CI or dev-container image that meets these points, the file can be
a single `FROM` line pointing at it.

**Why:** the factory knows nothing about the product's stack and never installs it. Everything
that runs in a sandbox (agents and verify) runs in this image.

**Template:** `templates/toolchain.Containerfile` (Node). A Gradle example is in
`docs/building-the-factory.md`, Module 1, "Dependency caches".

## Step 7. Declare dependency download directories

**What:** if the build tool downloads dependencies outside the worktree, add a label listing the
directories it downloads into (absolute paths, space-separated):

```dockerfile
LABEL factory.dep-cache="/opt/gradle-home/caches/modules-2"
```

List **only the directories holding downloaded artifacts**, never the tool's whole home: anything
in them carries over from the agent's calls into verify, outside the diff a reviewer sees.

| Build tool | `ENV` in the image | `factory.dep-cache` |
|---|---|---|
| Gradle | `GRADLE_USER_HOME=/opt/gradle-home` | `/opt/gradle-home/caches/modules-2` |
| Maven | `MAVEN_OPTS="-Dmaven.repo.local=/opt/m2"` | `/opt/m2` |
| sbt (coursier) | `COURSIER_CACHE=/opt/coursier` | `/opt/coursier` |
| Cargo | `CARGO_HOME=/usr/local/cargo` | `/usr/local/cargo/registry /usr/local/cargo/git` |
| Go | `GOMODCACHE=/opt/gomod` | `/opt/gomod` |
| npm, pip into a venv in the worktree | — | no label needed |

Only the Gradle row is tested.

**Why:** a task may add a dependency the image doesn't have. The agent downloads it while it has
network, and the factory keeps these directories per task so the offline verify still finds it.
Without the label the download is lost and verify fails.

**Template:** `templates/toolchain.Containerfile` (the commented `LABEL` line).

## Step 8. `scripts/deps`

**What:** a script that prints the product's direct dependencies, one name per line, sorted, with
no versions. It must:

- read the build files in the **current directory** (the runner runs it from the worktree root),
  and not `cd` relative to its own path;
- run **offline**, and read declarations without resolving them, so it works before a new
  dependency is downloaded;
- print names exactly as task files write them in `new_dependencies` (for example
  `com.squareup.okhttp3:okhttp` for Gradle, `express` for npm).

It doesn't need the executable bit: the runner runs it with `bash`.

**Why:** new dependencies are decided when the task is planned, and you approve them when you
commit the task file. The runner runs this script before and after each task. A direct
dependency the task added but its task file doesn't declare stops the task before commit and
review. The runner always uses `main`'s copy, so a task can't change how dependencies are
listed. Without the script, only the reviewer checks new dependencies.

**Template:** `templates/deps` (npm). A Gradle version is in `docs/building-the-factory.md`,
Module 1, "Template: `scripts/deps`".

## Step 9. Commit on `main` and check

**What:** commit everything above on `main`, then run from the factory:

```bash
~/factory-model/bin/check-product ~/projects/<product>          # the contract, as committed on main
~/factory-model/bin/build-worker ~/projects/<product>           # builds the worker image
~/factory-model/bin/check-product --run ~/projects/<product>    # verify in a fresh offline sandbox
```

The product is ready when the last command prints `Product meets the factory contract.`

**Why:** the checks see the product exactly as a task will: from `main`, sandboxed, offline. A
verify that passes on your machine but fails here would fail every task.

**Template:** none.
