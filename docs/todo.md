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
  Possible fix: extend the templates (`templates/deps` and the Gradle version in `docs/product/product-contract.md`, Step 7) to the
  missing kinds. Until then the reviewer role flags any change to build files or lockfiles.
- **`SANDBOX=bwrap` fails on hosts that restrict unprivileged user namespaces.** On Ubuntu 23.10+
  (`kernel.apparmor_restrict_unprivileged_userns = 1`), every `bin/sandbox` call in bwrap mode
  aborts before running the command: `bwrap: setting up uid map: Permission denied` (default
  network), or `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted` (`--net none`). So
  the bwrap fallback is unusable, and the "Try the sandbox" `--net none` check in
  `docs/building-the-factory.md` (Module 2) fails for the wrong reason and proves nothing.
  Possible fix: document the host setup in Module 2, an AppArmor profile for `/usr/bin/bwrap`
  that grants `userns` (as Ubuntu ships for other tools in `/etc/apparmor.d/`), and have
  `bin/sandbox` fail with a clear message pointing to it.
