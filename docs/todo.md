# To do

Known issues and missing features that are worth solving but not urgent. One bullet each: what's
wrong, where (files), what goes wrong because of it, and a possible fix if known. Remove a bullet
when it's fixed.

- **Product identity is the repo directory's basename, so worker images can collide.** `bin/sandbox`
  and `bin/build-worker` derive `<product>` from the basename of the product repo directory
  (`~/projects/<product>`), not from its full path. Two products whose repos share a basename
  (`~/projects/shop`, `~/work/shop`) both use the image `factory-worker-shop`, so building one
  overwrites the other's, and tasks of one product run in the other's toolchain. Possible fix:
  derive the name in one helper used by both scripts, from the basename plus a short hash of the
  absolute repo path.
- **The dependency gate only sees the dependency kinds `scripts/deps` lists.** `bin/run-task`
  (`docs/building-the-factory.md`, Module 3) compares `main`'s `scripts/deps` output before and
  after a task. The script reads build files in the worktree, which the agent can edit. Kinds the
  templates don't list pass unnoticed: the npm template reads only `dependencies` and
  `devDependencies` (not `optionalDependencies` or `peerDependencies`), and the Gradle version
  skips build-script plugins, `buildSrc/` and included builds. That matters most where
  dependencies install into the worktree (npm, a venv), because verify then doesn't catch them.
  Possible fix: extend the templates (`templates/deps` and the Gradle version in Module 1) to the
  missing kinds. Until then the reviewer role flags any change to build files or lockfiles.
