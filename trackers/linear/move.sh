#!/usr/bin/env bash
# usage: move.sh <key> <status>   sets a project's status, or an issue's workflow state, by its name
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ $# = 2 ] || die "usage: move.sh <key> <status>"
item "$1"
jq -e --arg s "$2" 'any(.[]; . == $s)' <<<"$STATUSES" >/dev/null || die "not a status: $2"
state=$(status_id "$KIND" "$2")
if [ "$KIND" = project ]; then
  q='mutation($id: String!, $s: String!) { projectUpdate(id: $id, input: {statusId: $s}) { success } }'
else
  q='mutation($id: String!, $s: String!) { issueUpdate(id: $id, input: {stateId: $s}) { success } }'
fi
gql "$q" "$(jq -n --arg id "$ID" --arg s "$state" '{id: $id, s: $s}')" >/dev/null
