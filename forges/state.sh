# Sourced by forge scripts. A task's forge state: key=value lines in $RUNDIR/forge-state.
state_get() { [ -f "$RUNDIR/forge-state" ] && sed -n "s/^$1=//p" "$RUNDIR/forge-state" | tail -1 || true; }
state_set() {
  local f="$RUNDIR/forge-state"
  { grep -v "^$1=" "$f" 2>/dev/null || true; echo "$1=$2"; } > "$f.tmp" && mv "$f.tmp" "$f"
}
die() { echo "forge $(basename "$(dirname "$0")"): $*" >&2; exit 1; }
id=$(basename "$RUNDIR"); branch=factory/$id; wt=$(cat "$RUNDIR/worktree")
