#!/usr/bin/env bash
# Local forge: where the review stands, from the branch and the decision bin/review recorded.
set -euo pipefail
. "$FACTORY_HOME/forges/state.sh"
[ -f "$RUNDIR/status" ] || { echo unsubmitted; exit 0; }          # still running
# merged: main contains the branch, and the branch holds the task's commit (a branch with no
# commits of its own, such as a red task's, is also contained in main)
if git -C "$PRODUCT" merge-base --is-ancestor "$branch" main 2>/dev/null \
   && git -C "$PRODUCT" log -1 --format=%s "$branch" | grep -q "^factory: $id\b"; then echo merged
elif [ "$(state_get decision)" = closed ]; then echo closed
elif [ -s "$RUNDIR/remarks.pending.md" ]; then echo changes-requested
elif [ "$(cat "$RUNDIR/status")" = green ] && { [ "$(cat "$RUNDIR/verdict" 2>/dev/null)" = approve ] \
     || ls "$RUNDIR"/user-review-*.md >/dev/null 2>&1; }; then echo pending   # after your review: even if the AI reviewer objects
else echo unsubmitted; fi
