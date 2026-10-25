#!/usr/bin/env bash
# Local forge: rebase factory/<id> onto main, then fast-forward main to it. History stays linear.
set -euo pipefail
. "$FACTORY_HOME/forges/state.sh"
[ "$(git -C "$PRODUCT" symbolic-ref -q --short HEAD)" = main ] || die "$PRODUCT is not on main"
[ -z "$(git -C "$PRODUCT" status --porcelain)" ] || die "$PRODUCT has uncommitted changes"
git -C "$wt" rebase -q main || { git -C "$wt" rebase --abort; die "$branch conflicts with main; nothing merged"; }
git -C "$PRODUCT" merge -q --ff-only "$branch"
