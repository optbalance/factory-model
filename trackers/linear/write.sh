#!/usr/bin/env bash
# usage: write.sh <key>|- <story>|- <title>   body on stdin; prints the item's key
# Key - and story -: creates a project (a story) in open. Key - and a story: creates an issue (a
# task) in that project, in the team TRACKER_PROJECT names, in todo. Both get TRACKER_LABEL. A
# key: replaces that item's title and body, leaving its status, labels and project alone.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ $# = 3 ] || die "usage: write.sh <key>|- <story>|- <title>"
body=$(mktemp); trap 'rm -f "$body"' EXIT
cat > "$body"                     # stored as Markdown: Linear may reformat it, keeping lines as lines

if [ "$1" != - ]; then
  item "$1"
  if [ "$KIND" = project ]; then
    vars=$(jq -n --arg id "$ID" --arg t "$3" --rawfile b "$body" '{id: $id, i: {name: $t, content: $b}}')
    gql 'mutation($id: String!, $i: ProjectUpdateInput!) { projectUpdate(id: $id, input: $i) { project { slugId } } }' \
      "$vars" | jq -r .projectUpdate.project.slugId
  else
    vars=$(jq -n --arg id "$ID" --arg t "$3" --rawfile b "$body" '{id: $id, i: {title: $t, description: $b}}')
    gql 'mutation($id: String!, $i: IssueUpdateInput!) { issueUpdate(id: $id, input: $i) { issue { identifier } } }' \
      "$vars" | jq -r .issueUpdate.issue.identifier
  fi
  exit 0
fi

team=$(team_id)
if [ "$2" = - ]; then
  state=$(status_id project open); label=$(label_id project)
  vars=$(jq -n --arg team "$team" --arg s "$state" --arg l "$label" --arg t "$3" --rawfile b "$body" \
    '{i: {teamIds: [$team], statusId: $s, labelIds: [$l], name: $t, content: $b}}')
  gql 'mutation($i: ProjectCreateInput!) { projectCreate(input: $i) { project { slugId } } }' "$vars" \
    | jq -r .projectCreate.project.slugId
else
  item "$2"; [ "$KIND" = project ] || die "not a story (project) key: $2"
  project=$(uuid); state=$(status_id issue todo); label=$(label_id issue)
  vars=$(jq -n --arg team "$team" --arg s "$state" --arg l "$label" --arg p "$project" --arg t "$3" \
    --rawfile b "$body" '{i: {teamId: $team, stateId: $s, labelIds: [$l], projectId: $p, title: $t, description: $b}}')
  gql 'mutation($i: IssueCreateInput!) { issueCreate(input: $i) { issue { identifier } } }' "$vars" \
    | jq -r .issueCreate.issue.identifier
fi
