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
`bin/start` loads this file (or the one `FACTORY_ENV` names) when it starts the orchestrator; the
factory never reads it otherwise. Mode 600 keeps the values from other users, not from programs
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
