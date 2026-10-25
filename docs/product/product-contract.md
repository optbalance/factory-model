# Product contract

What a product repo must provide before the factory can develop it. Work through the steps in
order; each one says what to add, why the factory needs it, and which file in
`factory-model/templates/` to start from. Templates are starting points: copy, then adapt them
to the product. Everything here lives in the **product** repo.

| Step | Product file | Template | Required |
|---|---|---|---|
| 1 | git repo with a `main` branch | — | always |
| 2 | `AGENTS.md` | `templates/AGENTS.md` | always |
| 3 | `scripts/verify` | `templates/verify` | always |
| 4 | `docs/specs/` | — | always |
| 5 | `toolchain.Containerfile` | `templates/toolchain.Containerfile` | with `SANDBOX=docker` (default) or `podman` |
| 6 | `factory.properties` | — | when you review on a forge such as GitHub |
| 7 | Commit on `main` and check | — | always |

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
knowledge they get for free, so it decides how well they work. The factory reads it from `main`
and puts it into every agent's system prompt itself, whatever the harness, so the product needs
no harness-specific copy such as `CLAUDE.md`. If you keep one for your own sessions, make it a
symlink to `AGENTS.md`.

**Template:** `templates/AGENTS.md`. Delete sections that don't apply rather than leaving them empty.

## Step 3. `scripts/verify`

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

## Step 4. `docs/specs/`

**What:** a committed `docs/specs/` directory. If it's empty, add `docs/specs/.gitkeep`, because
git doesn't track empty directories.

**Why:** specs and task files, the factory's work orders, are written here and committed on `main`
so every worktree has its own copy.

**Template:** none.

## Step 5. `toolchain.Containerfile`

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
  verify names the install command when they're missing (Step 3).
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

## Step 6. `factory.properties` (optional)

**What:** which forge you review and merge the product's tasks on. Without the file, it's
`local`: you review in your terminal with the factory's `bin/review`, and it merges into `main`.

```properties
# factory.properties (the defaults are shown)
forge=local          # local | github
forge.remote=origin  # the remote the factory pushes task branches to (not used by local)
```

With `forge=github`, every task that passes verify and the AI review is pushed as
`factory/<id>` and gets a pull request; you review, request changes or merge there. Also:

- the host has the GitHub CLI (`gh`) signed in, and `git push` to the remote works (factory
  contract);
- protect `main` on GitHub: require a pull request and an approving review. That's the real
  guard: the factory can push branches, so it must not be able to merge into `main` without you;
- push `main` before a batch: a pull request is against the remote's `main`, and the factory
  refuses to open one that would include commits only your local `main` has;
- optionally, turn on "Automatically delete head branches" in the repository settings.

Only these two keys. The file is read from `main` and parsed, never run, and never holds
credentials or machine paths: it's shared by everyone who works on the product.

**Why:** the factory has to know where a finished task goes for your review. The forge's code
lives in the factory (`forges/<name>/`); the product only names it.

**Template:** none.

## Step 7. Commit on `main` and check

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
