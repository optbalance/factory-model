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
tracker.project=ENG         # the team, project, board or repository the tracker reads
```

`bin/tracker` reads the file from `main` with the same parser as `bin/forge`: it never sources it,
and an unknown key or tracker stops it. `tracker.project` may also contain `/` (`owner/repo`). The
file never holds credentials; how this machine signs in to the tracker belongs to the machine
(factory contract).

```
bin/tracker name    <product-dir>                     the tracker's name
bin/tracker <op>    <product-dir> [args...]           runs trackers/<name>/<op>.sh
bin/tracker publish <product-dir> <story> <dir>       factory side: writes a plan's tasks (Step 4)
bin/tracker sync    <product-dir>                     factory side: one pass over the board (Module 11)
```

For a tracker operation it exports `FACTORY_HOME`, `PRODUCT`, `TRACKER_PROJECT` and
`TRACKER_STATE` (the product's state directory, Step 6), and runs the script with the operation's
arguments. `publish` and `sync` are the factory's own code, written once on top of the six
scripts; no tracker implements them.

## Step 2. The board: statuses and levels

**Two levels.** A *story* is a parent item: its body is the spec. A *task* is a child of a story:
its body is a task file. The tracker uses its own parent/child link (a sub-issue, a sub-task, a
story under an epic). Where the tracker has issue types, `tracker.parent-type` and
`tracker.child-type` in `factory.properties` name them; each tracker documents its defaults.
Deeper hierarchies are not part of the contract.

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
| `done` | every task is done or dropped | merged into `main` |
| `dropped` | abandoned | removed by a re-plan, or abandoned by you |

`dropped` is usually not a column: it is the tracker's closed, cancelled or archived state.
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
| `in-progress` → `done` | the factory | when every task is `done` or `dropped` |

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
| `items.sh [<story>]` | Lists the stories of `tracker.project`, or one story's tasks | one line per item, tab-separated: `key`, `status` (Step 2), `title` | 0, or 1 with the reason on stderr |
| `read.sh <key>` | Gets an item's body | the body, exactly as `write.sh` stored it | 0, or 1 |
| `write.sh <key>\|- <story>\|- <title>` | Creates the item (key `-`) or replaces its title and body; the body comes on stdin. A new story starts in `open`, a new task in `todo`; `<story>` makes it that story's child. Updating doesn't change the status | the item's key | 0, or 1 |
| `move.sh <key> <status>` | Sets the status, `dropped` included | nothing | 0, or 1 |
| `comment.sh <key>` | Posts the Markdown on stdin as a comment, marked as the factory's | nothing | 0, or 1 |
| `comments.sh <key>` | Takes the comments not taken yet, except the factory's own, oldest first, and records them as taken | each as `**<author>**, <time>:` then its body, or nothing | 0, or 1 |

`bin/tracker publish <product-dir> <story> <dir>` writes a plan, the files in `<dir>`, one task per
file: for each, `write.sh` with the existing key when a task of the story has that id in its
frontmatter, else `-`; then `move.sh dropped` for each task of the story whose id isn't in
`<dir>`. Running it twice changes nothing the second time.

## Step 5. Items: keys, bodies, comments

- **Keys.** `items.sh` and `write.sh` print a key that is safe in a git branch name after
  lowercasing: letters, digits and `-` only. A tracker converts its own (GitHub's `#42` → `42`) and
  accepts the converted form back in every script.
- **Task ids** are `<story key, lowercased>-TT-short-name` (`eng-12-02-csv-export`): unique across
  stories, so they name branches (`factory/<id>`) and run dirs as before. The planner chooses them;
  the tracker's key for a task is never used as its id.
- **A story's body** is the spec, in the format the spec skill writes.
- **A task's body** is a task file in the format of `templates/task.md`, frontmatter included,
  with `story: <key>` in place of `spec:`. `depends_on` lists task ids, or story keys (the story
  is `done`). The factory parses the frontmatter; the tracker never does. A tracker may mirror
  `depends_on` as its own "blocked by" links for display; the frontmatter wins.
- **Bodies round-trip.** `read.sh` returns byte for byte what `write.sh` stored. A tracker that
  rewrites Markdown (rich-text editors, block-based storage) keeps the body in a form it doesn't
  rewrite, such as a single code block; that's the tracker's job, not the factory's.
- **Editing.** You may edit a task's body in the tracker while its story is `refined`, or while
  the task is `todo` or `blocked`. A running task works from the copy the factory took when it
  started (the run dir's `task`), so an edit then counts only after the task is `blocked` and you
  move it to `todo`.
- **The factory's comments** carry a marker the tracker recognizes (a hidden HTML comment, a bot
  account): `comments.sh` never returns them.

## Step 6. State

A tracker keeps what it needs between calls in `$TRACKER_STATE/<key>`, `key=value` lines, through
`state_get` and `state_set` (the helper the forges use). `$TRACKER_STATE` is
`runs/tracker/<product>/`, outside the product repo. Keys in use:

| Key | Meaning |
|---|---|
| `comments` | the newest comment taken, so `comments.sh` gives each comment once |

`bin/tracker sync` keeps its own keys in the same files (Module 11). Because the state is on this
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

1. `bin/tracker name` reads `factory.properties` from `main`, and stops on an unknown key or
   tracker.
2. `write.sh -` creates an item and prints its key; `write.sh <key>` updates it without changing
   its status; `read.sh` returns the body byte for byte, frontmatter and code blocks included.
3. `items.sh` maps the board's statuses to Step 2's names, and gives `other` for any other one.
4. `comments.sh` gives a new comment once, never the factory's own; a second call prints nothing.
5. `bin/tracker publish` twice: the second run changes nothing; with a task removed from the plan,
   that task is `dropped`.
6. `bin/tracker sync` with stubbed agents takes a story from `todo` to `done` through each
   transition of Step 3, and a second `sync` after each step does nothing.
7. Then once against the real tracker, with a test project.
