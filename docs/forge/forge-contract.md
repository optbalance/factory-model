# Forge contract

What every `forges/<name>/` must provide. A forge is where you review a finished task and merge
it: `local` (your terminal, through `bin/review`) or a git host such as GitHub. Adapters wrap
harnesses; forges wrap git hosts. The design is in `docs/how-to/building-the-factory.md`,
Module 10.

Everything specific to one forge (its CLI, API, URLs, auth checks) lives only in
`forges/<name>/`. The rest of the factory calls a forge through `bin/forge` and works unchanged
with every forge.

| Step | What |
|---|---|
| 1 | How a forge is chosen and called |
| 2 | The four scripts |
| 3 | State |
| 4 | Rules |
| 5 | Check |

---

## Step 1. How a forge is chosen and called

A product names its forge in `factory.properties` at its root, committed on `main` (product
contract, Step 5). Without the file the forge is `local`:

```properties
forge=github          # local | github
forge.remote=origin   # the remote submit pushes to (not used by local)
```

`bin/forge` reads it from `main`, so a branch can't change where its own review goes. It parses
the file and never sources it: only `key=value` lines with values of letters, digits, `.`, `_`
and `-`, comments and blank lines. An unknown key or forge stops it. The file never holds
credentials or machine paths; how this machine signs in to the forge belongs to the machine
(factory contract).

```
bin/forge name   <product-dir>                    the forge's name
bin/forge remote <product-dir>                    the remote it pushes to
bin/forge <op>   <product-dir> <task-run-dir>     runs forges/<name>/<op>.sh
```

For an operation it exports `FACTORY_HOME`, `PRODUCT`, `RUNDIR` (the task's run dir) and
`FORGE_REMOTE`, and runs the script with `<product-dir> <task-run-dir>` as arguments. The task
id is the run dir's basename, the branch is `factory/<id>`, and the worktree's path is in
`$RUNDIR/worktree`. `forges/state.sh` sets `id`, `branch` and `wt`, and gives `state_get`,
`state_set` and `die`.

## Step 2. The four scripts

| Script | Does | Prints | Exit |
|---|---|---|---|
| `submit.sh` | Makes a green, approved task reviewable (after a rework, any green task: you reviewed it before, so you decide even if the AI reviewer objects). Idempotent: after a rework it runs again and updates the review | the review's URL, or nothing | 0, or 1 with the reason on stderr |
| `status.sh` | Asks where the review stands | one of `unsubmitted`, `pending`, `changes-requested`, `approved`, `merged`, `closed` | 0 |
| `remarks.sh` | Takes the remarks not taken yet, and records them as taken | the remarks as Markdown, or nothing | 0 |
| `merge.sh` | Merges an approved task into `main` | nothing | 0; 1 on a conflict (nothing merged); 3 when the forge merges in its own UI |

`status.sh` values:

| Value | Means | `bin/review sync` does |
|---|---|---|
| `unsubmitted` | Not ready for your review: still running, red, or not approved by the AI reviewer | nothing |
| `pending` | Waiting for you | nothing |
| `changes-requested` | You asked for changes, and their remarks haven't been taken yet | `bin/rework` |
| `approved` | You approved, not merged yet | nothing |
| `merged` | In `main` (on the forge: the pull request is merged) | update `main`, verify it, remove the worktree and branch |
| `closed` | You re-queued it, or closed the pull request | leaves it to orchestrate |

`remarks.sh` output is what the implementer reads: your words, with line comments as
`` `path:line`: comment ``. Only a decision to request changes produces remarks; plain comments
and approvals never do, so a discussion never starts an implementer.

`status.sh` reports on one task. Listing many is `bin/review status`'s job, so no forge
implements it.

## Step 3. State

A forge keeps what it needs between calls in `$RUNDIR/forge-state`, `key=value` lines, through
`state_get` and `state_set`. Keys in use:

| Key | Forge | Meaning |
|---|---|---|
| `decision` | local | `closed` after a re-queue in `bin/review` |
| `pushed` | github | the commit this run last pushed; the lease for the next push |
| `pr`, `url` | github | the pull request |
| `remarks` | github | the newest review whose remarks were taken |
| `answered` | github | how many `user-review-<n>.md` the pull request has been told about |

`bin/collect` and `bin/review status` show `url` when it's there.

The local forge also reads `$RUNDIR/remarks.pending.md`, which `bin/review` writes when you type
remarks.

## Step 4. Rules

- **Push only `factory/<id>`, and only with an explicit lease**
  (`--force-with-lease=refs/heads/factory/<id>:<last pushed>`, empty the first time). Never
  touch `main`.
- **Never push another machine's branch.** If the remote already has `factory/<id>` and
  `forge-state` has no `pushed`, someone else runs a task with this id: `submit.sh` refuses.
- **Never include unpushed commits from `main`.** A review against the remote's `main` would
  show them; `submit.sh` refuses until `main` is pushed.
- **Remarks count once.** After `remarks.sh` takes them, `status.sh` no longer says
  `changes-requested` for them.
- **Everything runs on the host**, with the host's sign-in. A forge token is never in
  `config/sandbox-env`, and agents can't push (the `git push` guard).
- **A CLI or a REST API, not MCP.** These are fixed steps; through MCP each would be a model
  call, configured per harness, with the forge's write access handed to an agent.

## Step 5. Check

With a throwaway product whose remote is a local bare repo (`git config
url.<bare-repo>.insteadOf <forge URL>`), and the forge's CLI replaced by a stub that logs its
calls:

1. `bin/forge name` reads `factory.properties` from `main`, and stops on an unknown key or forge.
2. `submit.sh` pushes and opens the review; a second call updates it; a branch someone else
   pushed is refused; unpushed `main` commits are refused.
3. `status.sh` gives `changes-requested` once per request; `remarks.sh` prints the remarks, then
   nothing.
4. `bin/review sync` reworks, then on `merged` updates `main`, verifies it and removes the
   worktree and branch.
5. Then once against the real forge, with a test repository.
