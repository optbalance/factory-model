#!/usr/bin/env bash
# GitHub forge: a closed pull request's task gets re-queued under the same id, so remove the
# branch from the remote, but only if it is still what this run last pushed (the same lease as
# submit.sh). A branch someone else pushed to is left alone. The pull request stays closed.
set -euo pipefail
. "$FACTORY_HOME/forges/state.sh"
pushed=$(state_get pushed)
[ -n "$pushed" ] || exit 0                                    # never pushed, or already discarded
if git -C "$PRODUCT" ls-remote --exit-code --heads "$FORGE_REMOTE" "refs/heads/$branch" >/dev/null; then
  git -C "$PRODUCT" push -q --force-with-lease="refs/heads/$branch:$pushed" "$FORGE_REMOTE" ":refs/heads/$branch" \
    || die "$branch on $FORGE_REMOTE isn't what this run last pushed (someone else pushed to it); not removed"
  echo "forge github: $branch removed from $FORGE_REMOTE"
fi
state_set pushed ""
