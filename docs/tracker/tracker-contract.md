# Tracker contract

What every `trackers/<name>/` must provide. A tracker is an issue tracker that holds a product's
stories and tasks, so that you drive the factory by moving cards on its board instead of talking
to an orchestrator session. Forges wrap git hosts; trackers wrap issue trackers. The design is in
`docs/how-to/building-the-factory.md`, Module 11.

A tracker is optional. Without one (`tracker=none`, the default) specs and task files live in the
product's `docs/specs/` and you run the spec, plan and orchestrate skills yourself, as before.
With one, **the tracker is the source of truth** for stories and tasks: nothing is kept in both
places, and nothing is synced between them.

Everything specific to one tracker (its CLI, API, URLs, auth checks, how it stores a body) lives
only in `trackers/<name>/`. The rest of the factory calls a tracker through `bin/tracker` and
works unchanged with every tracker.

| Step | What |
|---|---|
| 1 | How a tracker is chosen and called |
| 2 | The board: statuses and levels |
| 3 | Who moves what |
| 4 | The six scripts |
| 5 | Items: keys, bodies, comments |
| 6 | State |
| 7 | Rules |
| 8 | Check |

---

## Step 1. How a tracker is chosen and called

A product names its tracker in `factory.properties` at its root, committed on `main` (product
contract, Step 6), next to its forge:

```properties
tracker=linear              # none | <name of a trackers/ directory>
tracker.project=ENG         # where new items go: the team, project, board or repository
```

`bin/tracker` reads the file from `main` with the same parser as `bin/forge`
(`bin/lib/properties.sh`): it never sources it, reads only the `tracker` keys, and checks each
against its own pattern: `tracker` is lowercase letters, digits and `-`, and `tracker.project`
letters, digits, `.`, `_`, `-` and `/` (`owner/repo`). Keys only one tracker uses, such as
`tracker.parent-type`, are checked by that tracker. Any other value, or an unknown tracker, stops
it. The
file never holds credentials; how this machine signs in to the tracker belongs to the machine
(factory contract).

```
bin/tracker name    <product-dir>                     the tracker's name
bin/tracker <op>    <product-dir> [args...]           runs trackers/<name>/<op>.sh
bin/tracker publish <product-dir> <story> <dir>       factory side: writes a plan's tasks (Step 4)
bin/tracker sync    <product-dir>                     factory side: one pass over the board (Module 11)
```

For a tracker operation it exports `FACTORY_HOME`, `PRODUCT`, `TRACKER_PROJECT`, `TRACKER_LABEL`
(Step 2) and `TRACKER_STATE` (the product's state directory, Step 6), and runs the script with the operation's
arguments. `publish` and `sync` are the factory's own code, written once on top of the six
scripts; no tracker implements them.

## Step 2. The board: statuses and levels

**Two levels.** A *story* is a parent item: its body is the spec. A *task* is a child of a story:
its body is a task file. The tracker uses its own parent/child link (a sub-issue, a sub-task, a
story under an epic, an issue in a project). Where the tracker has issue types, `tracker.parent-type` and
`tracker.child-type` in `factory.properties` name them; each tracker documents its defaults.
Deeper hierarchies are not part of the contract.

**One label.** The factory sees only items labeled `factory:<product>`, where `<product>` is the
product repo's directory name, lowercased, as `bin/sandbox` names it (`factory:shovel`):
`TRACKER_LABEL`. Everything else on the board, other labels included, doesn't exist for it. You
put the label on a story to hand it to the factory; the factory puts it on every item it creates.
The label scopes a product, not a team or a board: several products can share one, a story can
carry several products' labels, and each product sees only its own tasks under it. You create the
label once in the tracker; the factory never creates labels.

**Eight statuses.** The board's statuses carry these names, compared case-insensitively with a
space and a `-` counted as equal (`In progress` is `in-progress`). There is no mapping config: you
name the board's columns this way when you set it up.

| Status | Story | Task |
|---|---|---|
| `open` | written, waiting for your approval | n/a |
| `todo` | approved: the factory plans it | waiting to run |
| `refined` | planned: its tasks wait for your approval | n/a |
| `in-progress` | tasks approved: the factory runs them | running, or being reworked |
| `blocked` | the planner has a question | the factory needs a decision (comment says what) |
| `in-review` | n/a | its review (pull request) waits for you |
| `done` | every task is done or canceled | merged into `main` |
| `canceled` | abandoned | removed by a re-plan, or abandoned by you |

`canceled` is usually not a column: it is the tracker's closed or canceled state.
`items.sh` reports any status outside these eight as `other`, and the factory ignores such items.

## Step 3. Who moves what

The factory acts when an item enters a status, and moves items only along the transitions below.
It never moves an item back after you moved it. Whether a task is merged is decided by git (`main`
has a commit whose subject starts with `factory: <id>`), not by its status, so a card dragged to
`done` by hand starts nothing.

```
Story:  open ─you─▶ todo ─factory: plan─▶ refined ─you─▶ in-progress ─factory─▶ done
                     ▲  │                   │
                     │  └─factory─▶ blocked │
                     └──you (answer)──┘     │
                     ▲──you (comments)──────┘

Task:   todo ─factory─▶ in-progress ─factory─▶ in-review ─you merge─▶ done (set by the factory)
          ▲                 │   ▲                  │
          │                 ▼   └─changes requested┘
          └──you (answer)── blocked ◀── review closed without a merge
```

Story:

| Transition | Who | What happens |
|---|---|---|
| `open` → `todo` | you | the factory plans the story: `refined`, or `blocked` with the questions as a comment |
| `blocked` → `todo` | you, after answering in comments | it plans again, with your comments |
| `refined` → `todo` | you, after commenting on the story or its tasks | it plans again: updates the tasks by id, adds new ones, drops removed ones |
| `refined` → `in-progress` | you | it starts the tasks |
| `in-progress` → `done` | the factory | when every task is `done` or `canceled` |

Task (only while its story is `in-progress`):

| Transition | Who | What happens |
|---|---|---|
| `todo` → `in-progress` | the factory | when every `depends_on` is merged, no running task's `touches` overlap, and fewer than 3 tasks of the product run |
| `in-progress` → `in-review` | the factory | green, approved by the AI reviewer, submitted to the forge; the comment links the review |
| `in-progress` → `blocked` | the factory | red, changes-needed after the last round, a failed review, or open questions; the comment has the summary |
| `blocked` → `todo` | you, after editing the task or answering in comments | it runs again from `main`, with your comments since the block; the earlier attempt is kept as `abandoned.patch` |
| `in-review` → `in-progress` | the factory | you requested changes in the review: rework |
| `in-review` → `done` | the factory | you merged the review |
| `in-review` → `blocked` | the factory | you closed the review without merging |

Code remarks go in the forge's review, never in tracker comments: the forge already routes them to
the implementer (forge contract), and two channels would need rules about which one wins.

## Step 4. The six scripts

| Script | Does | Prints | Exit |
|---|---|---|---|
| `items.sh [<story>]` | Lists the stories labeled `TRACKER_LABEL`, or one story's tasks labeled so | one line per item, tab-separated: `key`, `status` (Step 2), `title` | 0, or 1 with the reason on stderr |
| `read.sh <key>` | Gets an item's body | the body as Markdown, each line as `write.sh` or you wrote it (Step 5) | 0, or 1 |
| `write.sh <key>\|- <story>\|- <title>` | Creates the item (key `-`) or replaces its title and body; the body comes on stdin. A new item gets `TRACKER_LABEL` and goes to `tracker.project`; a new story starts in `open`, a new task in `todo`; `<story>` makes it that story's child. Updating doesn't change the status or the labels | the item's key | 0, or 1 |
| `move.sh <key> <status>` | Sets the status, `canceled` included | nothing | 0, or 1 |
| `comment.sh <key>` | Posts the Markdown on stdin as a comment, with the line `🏭 factory` before it | nothing | 0, or 1 |
| `comments.sh <key>` | Takes the comments not taken yet, except the factory's own, oldest first, and records them as taken | each as `**<author>**, <time>:` then its body, or nothing | 0, or 1 |

`bin/tracker publish <product-dir> <story> <dir>` writes a plan, the `*.md` files in `<dir>`, one
task per file:

1. It checks every file first, and writes nothing if one fails: each has an `id:` (lowercase
   letters, digits, `.`, `_`, `-`), no two share one, and a `story:` line, if there is one, names
   `<story>`.
2. For each file, `write.sh` with the key of the story's task that has that `id:`, else `-`. The
   title is the file's first `# ` heading, else its id.
3. `move.sh canceled` for each of the story's tasks whose id isn't in `<dir>`.

Canceled tasks are never matched, so a task the plan brings back is created again. A task without
an `id:` line (one you made by hand) is left alone, with a warning. It prints one line per task:
key, id, and `created`, `updated` or `canceled`. Running it twice changes nothing the second time.

## Step 5. Items: keys, bodies, comments

- **Keys.** `items.sh` and `write.sh` print a key that is safe in a git branch name after
  lowercasing: letters, digits and `-` only. A tracker converts its own (GitHub's `#42` → `42`) and
  accepts the converted form back in every script.
- **Task ids** are `<story key, lowercased>-TT-short-name` (`eng-12-02-csv-export`): unique across
  stories, so they name branches (`factory/<id>`) and run dirs as before. The planner chooses them;
  the tracker's key for a task is never used as its id.
- **Bodies are Markdown for people and models.** A story's body is the spec; a task's body is
  the task, written like `templates/task.md` (a reference, not a format). The tracker may
  reformat a body (escape characters, change list markers, add blank lines), as long as each line
  stays a line: `read.sh` never joins lines.
- **A task's fields** are lines of their own, each starting with its key, in any order:

  ```
  id: ntg-5-01-csv-export
  story: NTG-5
  depends_on: ntg-5-00-deps, NTG-4
  touches: src/reports/, src/api/export.ts
  ```

  The factory takes the first line starting with each key. A list is comma-separated, `[ ]`
  around it optional, and empty for none. A backslash before punctuation is dropped (`\[`, `\*`:
  Markdown escapes a tracker's editor adds). `depends_on` lists task ids, or story keys (the
  story is `done`). Everything else in the body is free text. The tracker never parses fields; it
  may mirror `depends_on` as its own "blocked by" links for display, and the field line wins.
- **Editing.** You may edit a task's body in the tracker while its story is `refined`, or while
  the task is `todo` or `blocked`. A running task works from the copy the factory took when it
  started (`runs/<timestamp>/<id>.md`), so an edit then counts only after the task is `blocked`
  and you move it to `todo`.
- **The factory's comments** start with the line `🏭 factory`, so you and a model can tell them
  from yours at a glance, and `comments.sh` skips every comment whose first line is that.
  Nothing else is marked: a body is whatever is in it now, whoever wrote it.

## Step 6. State

A tracker keeps what it needs between calls in `$TRACKER_STATE/<key>`, `name=value` lines, through
`kv_get <file> <name>` and `kv_set <file> <name> <value>` in `bin/lib/state.sh` (the forges'
state helper uses them too). `$TRACKER_STATE` is
`runs/tracker/<product>/`, outside the product repo. Keys in use:

| Key | Meaning |
|---|---|
| `comments` | the newest comment taken, so `comments.sh` gives each comment once |
| `plan` | a story's latest plan run dir (`bin/tracker sync`) |
| `run` | a task's latest run dir (`bin/tracker sync`) |

The keys a tracker uses and the factory's (`plan`, `run`) share the files, so a tracker never
names a key `plan` or `run`. Because the state is on this
machine, **one factory instance syncs a product's board.** A second machine would plan and run
the same items again; the forge's rule that `submit.sh` refuses a branch someone else pushed is
the backstop, not a way to share a board.

## Step 7. Rules

- **Everything runs on the host**, with the host's sign-in: the tracker's CLI login, or its token
  in the factory's secrets file (factory contract, Step 6). A tracker token is never in
  `config/sandbox-env`. Agents never call the tracker: the planner writes files, and
  `bin/tracker publish` writes them to the tracker.
- **A CLI or a REST/GraphQL API, not MCP.** These are fixed steps; through MCP each would be a
  model call, configured per harness, with the tracker's write access handed to an agent.
- **Idempotent.** Writes go by key, `publish` matches tasks by id, comments are taken once, so a
  second `sync` with nothing new on the board does nothing.
- **Triggers only wake the factory.** You, a timer or a webhook can start `bin/tracker sync`;
  `sync` reads the board's real state and never a webhook's payload. A lost or repeated event
  costs nothing. `sync` holds a lock per product, so two wake-ups can't run it twice at once.
- **Only the transitions of Step 3.** The factory never moves an item along any other transition,
  and never deletes one.

## Step 8. Check

With a throwaway product and project, and the tracker's CLI or API replaced by a stub that keeps
items in files and logs its calls:

1. `bin/tracker name` reads `factory.properties` from `main`, ignores keys it doesn't use, and
   stops on an unknown tracker.
2. `write.sh -` creates an item and prints its key; `write.sh <key>` updates it without changing
   its status; `read.sh` returns the body with every line kept as a line, and a task's field
   lines read back to the same values.
3. `items.sh` maps the board's statuses to Step 2's names, and gives `other` for any other one;
   it lists only items labeled `TRACKER_LABEL`, and `write.sh -` labels what it creates.
4. `comments.sh` gives a new comment once, never the factory's own; a second call prints nothing.
5. `bin/tracker publish` twice: the second run changes nothing; with a task removed from the plan,
   that task is `canceled`.
6. `bin/tracker sync` with stubbed agents takes a story from `todo` to `done` through each
   transition of Step 3, and a second `sync` after each step does nothing.
7. Then once against the real tracker, with a test project.
