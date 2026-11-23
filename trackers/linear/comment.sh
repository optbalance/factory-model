#!/usr/bin/env bash
# usage: comment.sh <key>   posts the Markdown on stdin as a comment on the project or issue, after
# the line 🏭 factory
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ $# = 1 ] || die "usage: comment.sh <key>"
item "$1"; target=$(uuid)
body=$(mktemp); trap 'rm -f "$body"' EXIT
{ echo "$FACTORY_LINE"; cat; } > "$body"
gql 'mutation($i: CommentCreateInput!) { commentCreate(input: $i) { success } }' \
  "$(jq -n --arg k "${KIND}Id" --arg t "$target" --rawfile b "$body" '{i: {($k): $t, body: $b}}')" >/dev/null
