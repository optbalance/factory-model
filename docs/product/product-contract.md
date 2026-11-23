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
| 4 | `docs/specs/` | — | without an issue tracker |
| 5 | `toolchain.Containerfile` | `templates/toolchain.Containerfile` | with `SANDBOX=docker` (default) or `podman` |
| 6 | `factory.properties` | — | when you review on a forge such as GitHub, or work from an issue tracker |
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

The factory's `spec` and `plan` skills name what they write; don't number files there by hand:

```
docs/specs/004-reporting.md                       spec NNN-name: the next free number
docs/specs/004-reporting/dependencies.md          the dependency changes it needs
docs/specs/004-reporting/tasks/004-02-csv-export.md    task NNN-TT-name: its id and branch factory/<id>
```

Other files in `docs/specs/` (your own docs) are fine: the skills count only `NNN-*` names. Each
task reaches `main` as one commit, `factory: <id>`.

**With an issue tracker** (Step 6), stories and tasks live in the tracker instead: a story's
body is the spec, a task's body its task file, and the factory writes nothing here. You don't
need the directory then.

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

**What:** which forge you review and merge the product's tasks on, and which issue tracker, if
any, holds its stories and tasks. Without the file, the forge is `local`: you review in your
terminal with the factory's `bin/review`, and it merges into `main`; and there is no tracker: you
work in a session, with the `spec`, `plan` and `orchestrate` skills.

```properties
# factory.properties (the defaults are shown)
forge=local          # local | github
forge.remote=origin  # the remote the factory pushes task branches to (not used by local)
tracker=none         # none | linear
tracker.project=     # with a tracker: the team, project or board new tasks go to (Linear: the team's key, ENG)
```

### The forge

With `forge=github`, every task that passes verify and the AI review is pushed as
`factory/<id>` and gets a pull request, opened as you (your `git` and `gh` sign-in). GitHub
doesn't let you approve or request changes on your own pull request, so you send remarks as a
review: "Review changes" → "Comment", with line comments. Your "Comment" reviews and anyone's
"Request changes" are remarks; a colleague's "Comment", approvals and conversation comments are
discussion. Merging is your approval; closing the pull request sends the task back to be
re-queued. Also:

- the host has the GitHub CLI (`gh`) signed in, and `git push` to the remote works (factory
  contract);
- `main` is guarded by the factory itself: agents never get push credentials (they run in the
  sandbox), and the factory's scripts push only `factory/<id>` branches. Branch protection on
  `main` (require a pull request) adds a guard against a mistake in those scripts, where your
  plan offers it: GitHub Free has none for private repositories. Don't require an approving
  review when you are the only reviewer: nobody could give it;
- push `main` before a batch: a pull request is against the remote's `main`, and the factory
  refuses to open one that would include commits only your local `main` has;
- optionally, turn on "Automatically delete head branches" in the repository settings.

### The tracker

With `tracker=<name>`, you work from the board: you write a story and move it to `todo`, the
factory plans it into tasks, you approve them by moving the story to `in-progress`, the factory
runs them and submits each to the forge, and you merge. The flow and who moves what are in
`docs/tracker/tracker-contract.md`, Steps 2 and 3, and in `docs/factory/operating-the-factory.md`.
Also:

- **Name the board's statuses** as the contract's Step 2 does, case and spaces aside (`In
  progress` is `in-progress`). A story uses `open`, `todo`, `refined`, `in-progress`, `blocked`,
  `done` and `canceled`; a task uses `todo`, `in-progress`, `blocked`, `in-review`, `done` and
  `canceled`. Items in any other status are ignored. With Linear, a story is a project and a
  task is an issue in it: name the workspace's project statuses (Settings → Projects →
  Statuses) and the team's workflow states this way: rename or add (Linear's defaults have no
  `Blocked`, and no `Open`, `Todo` or `Refined` project status). Extra ones such as `Backlog`
  may stay; the factory ignores items in them.
- **Label what the factory should take: `factory:<product>`**, `<product>` being the repo's
  directory name, lowercased (`factory:shovel`). The factory sees only items with that label and
  puts it on the tasks it creates; create the label once in the tracker. Several products can
  share a team or board. With Linear, create it twice: as a project label (for stories) and as an
  issue label of the workspace or of the `tracker.project` team (for tasks). Keep it a plain
  label, not inside a label group: an item takes only one label of a group.
- **Code remarks go in the forge's review**, never in tracker comments. Tracker comments answer
  the planner's questions, or say what to change in a story or a blocked task.
- the host signs in to the tracker, and a timer runs the factory's `bin/tracker sync` for the
  product (factory contract, Steps 9 and 10).

Only these keys. The file is read from `main` and parsed, never run, and never holds credentials
or machine paths: it's shared by everyone who works on the product.

**Why:** the factory has to know where a finished task goes for your review, and where your
stories are. The forge's and the tracker's code live in the factory (`forges/<name>/`,
`trackers/<name>/`); the product only names them.

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
