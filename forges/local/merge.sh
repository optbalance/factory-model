#!/usr/bin/env bash
# Local forge: rebase factory/<id> onto main, then add it to main as one commit, "factory: <id>",
# like a squash merge on a forge. A task's fix rounds and reworks don't each land on main.
set -euo pipefail
. "$FACTORY_HOME/forges/state.sh"
[ "$(git -C "$PRODUCT" symbolic-ref -q --short HEAD)" = main ] || die "$PRODUCT is not on main"
[ -z "$(git -C "$PRODUCT" status --porcelain)" ] || die "$PRODUCT has uncommitted changes"
git -C "$wt" rebase -q main || { git -C "$wt" rebase --abort; die "$branch conflicts with main; nothing merged"; }
c=$(git -C "$PRODUCT" commit-tree "$branch^{tree}" -p main -m "factory: $id" -m "Task: $(cat "$RUNDIR/task")")
git -C "$PRODUCT" merge -q --ff-only "$c"
state_set merged "$c"
