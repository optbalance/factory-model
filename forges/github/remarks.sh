#!/usr/bin/env bash
# GitHub forge: the reviews with remarks not taken yet (lib.sh), with their line comments, as
# Markdown; then records them as taken. Plain conversation comments and approvals are never remarks.
set -euo pipefail
. "$FACTORY_HOME/forges/state.sh"; . "$(dirname "$0")/lib.sh"
[ -n "$pr" ] || exit 0
ids=$(remark_reviews "$(state_get remarks)")
[ -n "$ids" ] || exit 0
for r in $ids; do
  printf '## Review %s\n\n' "$r"
  gh api "repos/{owner}/{repo}/pulls/$pr/reviews/$r" --jq '.body'
  echo
  gh api --paginate "repos/{owner}/{repo}/pulls/$pr/reviews/$r/comments" \
    --jq '.[] | "- `\(.path)\(if .line then ":\(.line)" elif .original_line then ":\(.original_line)" else "" end)`: \(.body | gsub("\n"; "\n  "))"'
  echo
done
state_set remarks "$(tail -1 <<<"$ids")"
