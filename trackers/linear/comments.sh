#!/usr/bin/env bash
# usage: comments.sh <key>   the project's or issue's comments not taken yet, oldest first, except
# the factory's own (first line 🏭 factory), each as **<author>**, <time>: and its body. The newest
# one seen is recorded in $TRACKER_STATE/<key> as `comments`, so each comment is given once.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$FACTORY_HOME/bin/lib/state.sh"
[ $# = 1 ] || die "usage: comments.sh <key>"
item "$1"; state="$TRACKER_STATE/$ID"; target=$(uuid)
# The top-level comments query: a project's own comments field comes back empty.
since=$(kv_get "$state" comments); since=${since:-1970-01-01T00:00:00.000Z}
new=$(gql 'query($f: CommentFilter!) { comments(first: 250, filter: $f) { nodes { createdAt body user { name } } } }' \
        "$(jq -n --arg k "$KIND" --arg t "$target" --arg s "$since" '{f: {($k): {id: {eq: $t}}, createdAt: {gt: $s}}}')" \
  | jq '.comments.nodes | sort_by(.createdAt)')
[ "$(jq length <<<"$new")" -gt 0 ] || exit 0
jq -r --arg line "$FACTORY_LINE" '.[] | select((.body | split("\n")[0]) != $line)
  | "**\(.user.name // "unknown")**, \(.createdAt):\n\(.body)\n"' <<<"$new"
kv_set "$state" comments "$(jq -r '.[-1].createdAt' <<<"$new")"
