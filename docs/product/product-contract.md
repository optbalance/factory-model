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
| 7 | `scripts/deps` | `templates/deps` | if dependencies install into the worktree (npm, a venv); recommended otherwise |
| 8 | Commit on `main` and check | — | always |

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
- "never touch" areas: generated code, applied migrations, public contracts, and dependency
  declarations and lockfiles (dependency changes land on `main` before tasks run);
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
- **Using fully qualified image names** (`FROM docker.io/library/eclipse-temurin:21-jdk-noble`, not
  `eclipse-temurin:21-jdk-noble`). Docker assumes `docker.io` for a short name; Podman refuses it
  unless the host's `registries.conf` lists a search registry.
- **Usable by any user.** Commands run as your user ID with `HOME=/tmp`. Install tools system-wide
  (`/usr/local`, `/opt`), never under `/root` or `~`.
- **Using fixed cache paths.** Point every tool cache at a fixed path with `ENV`, and make it
  writable by any user (`chmod -R a+rwX`). Don't rely on `~`: JVM tools (Gradle, Maven, sbt) take
  it from `user.home`, which comes from `/etc/passwd`, not from `$HOME`, and the sandbox's user ID
  usually has no entry there. Go and Cargo use `$HOME`, which is `/tmp` and empty on every call.
  Examples (only Gradle is tested):

  | Build tool | `ENV` in the image |
  |---|---|
  | Gradle | `GRADLE_USER_HOME=/opt/gradle-home` |
  | Maven | `MAVEN_OPTS="-Dmaven.repo.local=/opt/m2"` |
  | sbt (coursier) | `COURSIER_CACHE=/opt/coursier` |
  | Cargo | `CARGO_HOME=/usr/local/cargo` |
  | Go | `GOMODCACHE=/opt/gomod` |
  | npm, pip into a venv in the worktree | nothing: they install into the worktree |

- **Complete offline for `main`.** The toolchain, the build tool's own distribution (for example
  the Gradle wrapper's) and every dependency `main` declares are in the image. To pre-fetch, `COPY`
  only the build files (not the sources), so a source change doesn't trigger a re-download.
  `node_modules` and a venv live in the worktree instead: the implementer installs them, and
  verify names the install command when they're missing (Step 4).
- **Free of `ENTRYPOINT` requirements.** The factory clears it and runs commands directly.

If the product already has a CI or dev-container image that meets these points, the file can be
a single `FROM` line pointing at it.

**Why:** the factory knows nothing about the product's stack and never installs it. Everything
that runs in a sandbox (agents and verify) runs in this image. Tasks never change dependencies:
approved changes are committed on `main` first, and the factory rebuilds this image from `main`
before every batch, so it always holds what the tasks need.

With `SANDBOX=bwrap` there's no image: the toolchain and `main`'s dependencies have to be on the
host, in paths listed in `SANDBOX_RO_PATHS`.

**Template:** `templates/toolchain.Containerfile` (Node).

A Gradle example. The wrapper's Gradle distribution is baked in by running `./gradlew` once, so
`gradle-wrapper.properties` stays the only place that sets the Gradle version. Gradle has no
"download everything" command (`dependencies` only prints the tree, and compile tasks skip
resolution when there are no sources), so an init script resolves every configuration:

```dockerfile
FROM docker.io/library/eclipse-temurin:21-jdk-noble
ENV GRADLE_USER_HOME=/opt/gradle-home
WORKDIR /opt/prefetch
COPY gradlew settings.gradle build.gradle ./
COPY gradle/ gradle/
COPY app/build.gradle app/                       # one line per subproject
RUN printf '%s\n' 'allprojects { tasks.register("resolveAll") { doLast { configurations.findAll { it.canBeResolved }.each { it.resolve() } } } }' > /tmp/resolve.gradle \
 && ./gradlew --no-daemon -q --init-script /tmp/resolve.gradle resolveAll \
 && rm -rf /opt/prefetch /tmp/resolve.gradle "$GRADLE_USER_HOME/daemon" \
 && chmod -R a+rwX "$GRADLE_USER_HOME"
WORKDIR /
```

## Step 7. `scripts/deps`

**What:** a script that prints the product's direct dependencies with their declared versions,
one per line, sorted. It must:

- read the build files in the **current directory** (the runner runs it from the worktree root),
  and not `cd` relative to its own path;
- run **offline**, and read declarations without resolving them, so it still works when a task
  declared a dependency the image doesn't have;
- change its output whenever a dependency is added, removed, or changes version.

It doesn't need the executable bit: the runner runs it with `bash`.

**Why:** tasks never change dependencies; changes are planned, approved, and committed on `main`
before the tasks run. The runner runs `main`'s copy of this script before and after each task and
stops a task whose output changed (status `deps-changed`). It's required when dependencies install
into the worktree (npm, a venv): an agent could install one there, and verify would still pass.
For build tools that download outside the worktree, verify already fails offline on a dependency
the image doesn't have; the script turns that into a clear status instead of wasted fix rounds.

**Template:** `templates/deps` (npm).

A Gradle version. An init script prints the external dependencies each configuration declares,
without resolving them (build-script plugins aren't included; the version is `null` when a
platform or BOM sets it):

```bash
#!/usr/bin/env bash
# scripts/deps: the product's direct dependencies with their declared versions, one per line, sorted.
# Offline, from the current directory. The runner compares its output before and after each task.
set -euo pipefail
init=$(mktemp); trap 'rm -f "$init"' EXIT
cat > "$init" <<'EOF'
allprojects { tasks.register("listDeps") { doLast {
  configurations.each { c -> c.dependencies.withType(ExternalModuleDependency).each { println "${it.group}:${it.name}:${it.version}" } }
} } }
EOF
./gradlew -q --offline --no-configuration-cache --init-script "$init" listDeps | sort -u
```

## Step 8. Commit on `main` and check

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
