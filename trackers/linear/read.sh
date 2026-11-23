#!/usr/bin/env bash
# usage: read.sh <key>   prints the story's (project's) content or the task's (issue's) description,
# as Linear's Markdown
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ $# = 1 ] || die "usage: read.sh <key>"
item "$1"
field=$([ "$KIND" = project ] && echo content || echo description)
gql "query(\$id: String!) { $KIND(id: \$id) { body: $field } }" "$(id_vars)" | jq -r ".$KIND.body // empty"
