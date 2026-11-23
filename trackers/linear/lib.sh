# Sourced by the Linear tracker scripts. Linear's GraphQL API through curl and jq, signed in with a
# personal API key: LINEAR_API_KEY, from the environment or the factory's secrets file.
# A story is a Linear project, its key the project's slugId (df9d7ddeed9a), its body the project's
# content, its status one of the workspace's project statuses. A task is an issue in that project,
# its key the issue's identifier (NTG-12), its body the description, its status one of the team's
# workflow states. TRACKER_PROJECT is the key of the team new tasks go to (NTG). TRACKER_LABEL
# (factory:shovel) is a project label on the product's stories and an issue label on its tasks.
die() { echo "tracker linear: $*" >&2; exit 1; }
command -v curl >/dev/null && command -v jq >/dev/null || die "curl and jq are needed on the host"
. "$FACTORY_HOME/bin/lib/env.sh"
factory_env_load LINEAR_API_KEY
[ -n "${LINEAR_API_KEY:-}" ] || die "LINEAR_API_KEY is not set (add it to ${factory_env/#$HOME/\~})"

# The contract's statuses (Step 2), and the first line of every comment the factory posts (Step 5)
STATUSES='["open","todo","refined","in-progress","blocked","in-review","done","canceled"]'
FACTORY_LINE='🏭 factory'

# gql <query> [variables-json]: prints the response's data. The key goes through a file descriptor,
# never on a command line where other users' ps would see it.
gql() {
  local resp
  resp=$(jq -n --arg q "$1" --argjson v "${2:-{\}}" '{query: $q, variables: $v}' \
    | curl -sS --fail-with-body -H @<(printf 'Authorization: %s\n' "$LINEAR_API_KEY") \
        -H 'Content-Type: application/json' --data @- https://api.linear.app/graphql) \
    || die "request failed: ${resp:-no response}"
  jq -e '.errors == null' >/dev/null <<<"$resp" || die "$(jq -c .errors <<<"$resp")"
  jq '.data' <<<"$resp"
}

# item <key>: sets KIND (project or issue) and ID (the slugId, or the identifier). Keys may come
# back lowercased (ntg-12). Call it directly, not in $( ), so that die stops the script.
item() {
  if [[ $1 =~ ^[0-9a-fA-F]{12}$ ]]; then KIND=project ID=${1,,}
  elif [[ $1 =~ ^[A-Za-z]+-[0-9]+$ ]]; then KIND=issue ID=${1^^}
  else die "not a project or issue key: $1"; fi
}

# id_vars: {"id": ID}, the variables of a query by key
id_vars() { jq -n --arg id "$ID" '{id: $id}'; }

# uuid: the item's internal id, for inputs that take only that
uuid() { gql "query(\$id: String!) { $KIND(id: \$id) { id } }" "$(id_vars)" | jq -er ".$KIND.id"; }

# team_id: the id of the team TRACKER_PROJECT names
team_id() {
  gql 'query($k: String!) { teams(filter: {key: {eq: $k}}) { nodes { id } } }' \
      "$(jq -n --arg k "$TRACKER_PROJECT" '{k: $k}')" \
    | jq -er '.teams.nodes[0].id // empty' || die "no team with the key $TRACKER_PROJECT"
}

# label_id <project|issue>: the id of the project label, or the issue label of the workspace or the
# team, that TRACKER_LABEL names
label_id() {
  local f=${1}Labels
  gql "query(\$n: String!) { $f(filter: {name: {eqIgnoreCase: \$n}}) { nodes { id team { key } } } }" \
      "$(jq -n --arg n "$TRACKER_LABEL" '{n: $n}')" \
    | jq -er --arg k "$TRACKER_PROJECT" "first(.$f.nodes[] | select(.team == null or .team.key == \$k) | .id) // empty" \
    || die "no $1 label named $TRACKER_LABEL (create it in Linear's settings, Labels)"
}

# norm: a status name as the contract writes it (In Progress → in-progress), in jq
NORM='ascii_downcase | gsub(" "; "-")'

# status_id <project|issue> <status>: the id of the project status, or the team's workflow state,
# with the contract's name
status_id() {
  local q at
  if [ "$1" = project ]; then q='{ projectStatuses { nodes { id name } } }'; at=.projectStatuses
  else
    q='query($k: String!) { teams(filter: {key: {eq: $k}}) { nodes { states { nodes { id name } } } } }'
    at='.teams.nodes[0].states'
  fi
  gql "$q" "$(jq -n --arg k "$TRACKER_PROJECT" '{k: $k}')" \
    | jq -er --arg s "$2" "first($at.nodes[] | select(.name | $NORM == \$s) | .id) // empty" \
    || die "no $1 status named $2"
}
