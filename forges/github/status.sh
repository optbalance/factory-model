#!/usr/bin/env bash
# GitHub forge: where the pull request's review stands. "Request changes" counts once: after its
# remarks are taken (remarks.sh), the pull request is pending again until you review again.
set -euo pipefail
. "$FACTORY_HOME/forges/state.sh"; . "$(dirname "$0")/lib.sh"
[ -n "$pr" ] || { echo unsubmitted; exit 0; }
read -r state decision < <(gh pr view "$pr" --json state,reviewDecision --jq '"\(.state) \(.reviewDecision // "")"')
case "$state" in
  MERGED) echo merged; exit 0 ;;
  CLOSED) echo closed; exit 0 ;;
esac
if [ -n "$(changes_requested "$(state_get remarks)")" ]; then echo changes-requested
elif [ "${decision:-}" = APPROVED ]; then echo approved
else echo pending; fi
