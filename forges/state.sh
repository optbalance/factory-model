# Sourced by forge scripts. A task's forge state: key=value lines in $RUNDIR/forge-state.
. "$FACTORY_HOME/bin/lib/state.sh"
state_get() { kv_get "$RUNDIR/forge-state" "$1"; }
state_set() { kv_set "$RUNDIR/forge-state" "$1" "$2"; }
die() { echo "forge $(basename "$(dirname "$0")"): $*" >&2; exit 1; }
id=$(basename "$RUNDIR"); branch=factory/$id; wt=$(cat "$RUNDIR/worktree")
