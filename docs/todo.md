# To do

Known issues and missing features that are worth solving but not urgent. One bullet each: what's
wrong, where (files), what goes wrong because of it, and a possible fix if known. Remove a bullet
when it's fixed.

- **Product identity is the repo directory's basename, so names can collide.** `bin/sandbox` and
  `bin/build-worker` derive `<product>` from the basename of the product repo directory
  (`~/projects/<product>`), not from its full path.
  - Worker image: two products whose repos share a basename (`~/projects/shop`, `~/work/shop`)
    both use `factory-worker-shop`, so building one overwrites the other's image.
  - Dependency-cache volumes: named `factory-dep-<product>-<worktree basename>-<n>`, and
    `bin/sandbox` reuses any existing volume with that name. Two such products with the same task
    ID share a volume, and see each other's downloads. A task re-run with the same ID reuses the
    old volume if `bin/dep-cache drop` wasn't run after the first attempt.
  - `bin/dep-cache` itself is not affected: it finds volumes by their `factory.worktree` label,
    which holds the full path.
  - Possible fix: derive the name in one helper used by both scripts, from the basename plus a
    short hash of the absolute repo path. Have `bin/sandbox` refuse to reuse a volume whose
    `factory.worktree` label doesn't match the current worktree, and have `bin/fan-out` run
    `bin/dep-cache drop` before it creates a task's worktree, so a re-run starts clean.
- **The dependency gate trusts what `scripts/deps` can see, and the agent controls the files it
  reads.** `bin/run-task` (`docs/building-the-factory.md`, Module 3) runs `main`'s copy of
  `scripts/deps` on the worktree, so deleting or editing the script on the task branch changes
  nothing. But the agent can change the build files the script reads:
  - Dependency kinds the script doesn't list pass unchecked: the npm template reads only
    `dependencies` and `devDependencies` (not `optionalDependencies` or `peerDependencies`), and the
    Gradle version skips build-script plugins, `buildSrc/` and included builds.
  - Build-file changes that make the script print less (in the worst case nothing) read as
    "nothing added": `comm` only compares lines, so a shrunken list passes the gate.
  - Possible fix: in `run-task`, set the status to `red` when `deps.after` is empty but
    `deps.before` isn't, and list removed dependencies (`comm -23 deps.before deps.after`) for the
    reviewer. Extend the templates to cover the missing dependency kinds, and have the reviewer
    role check build-file changes that could hide a dependency from `scripts/deps`.
