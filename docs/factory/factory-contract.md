# Factory contract

What a machine must provide before the factory can run. Work through the steps in order. The
explanations and the code behind each step are in `docs/how-to/building-the-factory.md`; what each
product must provide is in `docs/product/product-contract.md`. How to run the factory once this is
done is in `docs/factory/operating-the-factory.md`.

| Step | What | Where it lives | Required |
|---|---|---|---|
| 1 | Host tools | the host | always |
| 2 | The factory repo and `FACTORY_HOME` | `~/factory-model` | always |
| 3 | A sandbox backend | the host | always |
| 4 | The orchestrator harness, signed in | the host | always |
| 5 | Secret names | `config/sandbox-env` (committed) | always |
| 6 | Secret values | `~/.config/factory/env` (outside every repo) | always |
| 7 | Routing | `config/routing.json` (committed) | from Module 3 |
| 8 | Check | — | always |
| 9 | Forge and tracker sign-in | the host | for products reviewed on a forge, or with a tracker (product contract, Step 6) |
| 10 | A timer for the board | the host's crontab | for products with a tracker (product contract, Step 6) |

---

## Step 1. Host tools

`bash` 4+, `git` 2.31+ (`--path-format`), `jq`, and GNU coreutils and findutils. The factory
scripts run on the host, outside any sandbox.

## Step 2. The factory repo and `FACTORY_HOME`

Clone the factory once, for example to `~/factory-model`. Products live in their own repos
(`~/projects/<product>`), never inside it.

`FACTORY_HOME` is the factory's path. `bin/start` and `bin/sandbox` set it themselves. For harness
sessions you start without `bin/start`, export it in your shell profile
(`export FACTORY_HOME=~/factory-model`), because the guards need it.

## Step 3. A sandbox backend

Every agent call and every verify run happens in a sandbox. Choose one with `SANDBOX`:

| `SANDBOX` | Needs | Notes |
|---|---|---|
| `docker` (default) | Docker, usable by your user without `sudo` | |
| `podman` | rootless Podman | |
| `bwrap` | bubblewrap; the toolchain and harnesses installed on the host | Blocked on Ubuntu 23.10+ by AppArmor (see `docs/todo.md`) |
| `none` | nothing | No isolation. Only for debugging the factory itself |

The container backends run each product's worker image, built per product (see
`operating-the-factory.md`, "Plug in a product").

## Step 4. The orchestrator harness, signed in

The orchestrator is an interactive harness session on the host, for example Claude Code. Install
it on the host and sign in as usual. Worker harnesses don't need a host install: they're in the
worker image, and they authenticate with the secrets from Steps 5–6, never with your host sign-in.

## Step 5. Secret names: `config/sandbox-env`

One variable name per line, never values. Only these names (plus `FACTORY_HOME`) cross into a
sandbox; everything else in your environment stays out. List what your worker harnesses need:

| Harness | Name | Value from |
|---|---|---|
| Claude Code, subscription | `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` on the host (prints a one-year `sk-ant-oat01-…` token) |
| Claude Code, API billing | `ANTHROPIC_API_KEY` | the Claude Console |
| Codex | `CODEX_API_KEY` | the OpenAI platform |
| Antigravity (`agy`) | `GEMINI_API_KEY` | Google AI Studio |
| Pi | the key of the provider it uses, e.g. `ANTHROPIC_API_KEY` | that provider |

Set only one Claude Code variable: if both are set, the API key wins and usage is billed. Don't
list npm, GitHub or cloud tokens.

## Step 6. Secret values: `~/.config/factory/env`

The values live in one file outside every repo, readable only by your user:

```bash
mkdir -p ~/.config/factory
install -m 600 /dev/null ~/.config/factory/env     # once: creates an empty file, mode 600
nano ~/.config/factory/env                         # add NAME=value lines: no spaces around =, no quotes
```

Type secrets in an editor, not on the command line, where they'd land in your shell history.
`bin/start` loads this file (or the one `FACTORY_ENV` names) into whatever it starts: the
orchestrator, or a factory script such as `bin/tracker sync` from a timer (Step 10). `bin/sandbox`
and the tracker scripts also read a name from it when it is missing from the environment
(`bin/lib/env.sh`). Mode 600 keeps the values from other users, not from programs
running as you: the orchestrator session can read them.

## Step 7. Routing: `config/routing.json`

Which harness and model runs each role. `bin/build-worker` also reads it to decide which harness
layers go into the worker image. Format: `docs/how-to/building-the-factory.md`, Module 3.

## Step 8. Check

```bash
~/factory-model/bin/check-factory      # the layout is complete: "All good, structure complete"
~/factory-model/guards/test.sh         # the guards behave: "guards: all N cases passed"
```

Then plug in a product (`operating-the-factory.md`).

## Step 9. Forge and tracker sign-in

Only for a product whose `factory.properties` names a forge other than `local`. Forge calls run
on the host, never in a sandbox, with the host's own sign-in:

| Forge | Needs |
|---|---|
| `github` | `git push` to the product's remote works (SSH key or credential helper); the GitHub CLI `gh` is installed and `gh auth status` succeeds, with access to pull requests and contents |

Never put a forge token in `config/sandbox-env`: agents never talk to the forge.

A product whose `factory.properties` names a tracker needs the host signed in to it the same way:
tracker calls run on the host, through `bin/tracker`, never in a sandbox.

| Tracker | Needs |
|---|---|
| `linear` | `curl` and `jq` on the host; a personal API key (Linear's settings, Security & access) of a member of the product's team, in the secrets file (Step 6) as `LINEAR_API_KEY=<key>` |

Check it with `bin/tracker items ~/projects/<product>`: it lists the team's stories. Never put a
tracker token in `config/sandbox-env` either: the planner writes files, and `bin/tracker` writes
them to the tracker. The factory acts as you on the board (`docs/todo.md` lists a dedicated user).

**Unattended (Step 10).** `gh auth login` keeps its token in the desktop keyring, which a timer
can't open after a reboot with nobody logged in: `gh auth status` then says "Failed to log in".
Put the token in the secrets file (Step 6) as `GH_TOKEN=<token>` (from `gh auth token`, or a
fine-grained token with pull requests and contents on the product's repository); `bin/start`
exports it, and `gh` uses it before the keyring. `git push` needs an SSH key without a
passphrase, or a credential helper that needs no session, for the same reason.

## Step 10. A timer for the board

Only for a product whose `factory.properties` names a tracker. The board drives the factory only
if something runs `bin/tracker sync` (`docs/how-to/building-the-factory.md`, Module 11): one
crontab line per product, every 5 minutes. `crontab -e`, then:

```
*/5 * * * * ~/factory-model/bin/start ~/factory-model/bin/tracker sync ~/projects/<product> >> ~/factory-model/runs/sync-<product>.log 2>&1
```

- **Absolute paths.** cron starts in your home directory, with a bare `PATH` (`/usr/bin:/bin`):
  the host tools of Step 1, `docker` or `podman`, `curl` and `flock` must be there. The harness
  runs in the worker image, so it needs no host install. `~` works in a crontab line.
- **Secrets through `bin/start`**, as for any factory script: cron has no shell profile.
- **Runs without a login**, after a reboot too, with no setup (a systemd user timer would need
  `loginctl enable-linger`). Every sign-in the factory uses must work without your session: the
  tracker's and the harness's tokens are in the secrets file already; the forge, see Step 9.
- **The log** gets a dated line for each thing `sync` does, and nothing for a pass with nothing
  to do. An idle pass is one tracker call, so 5 minutes is cheap; it is also the longest you wait
  between moving a card and the factory acting on it.
- **Overlaps are safe:** `sync` holds a lock per product, so a pass that runs long makes the next
  one exit at once. Run `bin/tracker sync` by hand whenever you don't want to wait. `bin/review
  sync` and approve in `bin/review` hold their own lock per product while they merge: if one of
  them is running, the other says so and stops, and a timer's pass starts no new task until the
  next one.
- **To pause** a product, comment its line out. Runs already started finish; nothing new starts.

Check, once, as cron would run it: `env -i HOME=$HOME PATH=/usr/bin:/bin ~/factory-model/bin/start
~/factory-model/bin/tracker sync ~/projects/<product>` exits 0. To test the forge as a timer
after a reboot would, add `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent` before `gh auth
status`.
