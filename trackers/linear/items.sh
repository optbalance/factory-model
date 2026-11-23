#!/usr/bin/env bash
# usage: items.sh [<story>]   the projects (stories), or one project's issues (tasks), that carry
# TRACKER_LABEL: key, status, title, tab-separated. A status whose name isn't one of the contract's
# is `other`.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ $# -le 1 ] || die "usage: items.sh [<story>]"
if [ $# = 1 ]; then
  item "$1"; [ "$KIND" = project ] || die "not a story (project) key: $1"
  vars=$(jq -n --arg id "$ID" --arg l "$TRACKER_LABEL" '{id: $id, l: $l}'); at=.project.issues
  q='query($id: String!, $l: String!, $after: String) { project(id: $id) {
       issues(first: 100, after: $after, filter: {labels: {some: {name: {eqIgnoreCase: $l}}}}) {
       pageInfo { hasNextPage endCursor } nodes { key: identifier title status: state { name } } } } }'
else
  vars=$(jq -n --arg l "$TRACKER_LABEL" '{l: $l}'); at=.projects
  q='query($l: String!, $after: String) {
       projects(first: 100, after: $after, filter: {labels: {some: {name: {eqIgnoreCase: $l}}}}) {
       pageInfo { hasNextPage endCursor } nodes { key: slugId title: name status { name } } } }'
fi
after=null
while :; do
  res=$(gql "$q" "$(jq -c --argjson a "$after" '. + {after: $a}' <<<"$vars")" | jq "$at")
  jq -r --argjson known "$STATUSES" ".nodes[] | (.status.name | $NORM) as \$s
    | [.key, (if any(\$known[]; . == \$s) then \$s else \"other\" end), (.title | gsub(\"[\t\r\n]\"; \" \"))]
    | @tsv" <<<"$res"
  [ "$(jq -r .pageInfo.hasNextPage <<<"$res")" = true ] || break
  after=$(jq .pageInfo.endCursor <<<"$res")
done
