#!/usr/bin/env bash
# Local forge: the remarks you wrote in bin/review, once.
set -euo pipefail
. "$FACTORY_HOME/forges/state.sh"
f="$RUNDIR/remarks.pending.md"
[ -s "$f" ] || exit 0
cat "$f"; rm "$f"
