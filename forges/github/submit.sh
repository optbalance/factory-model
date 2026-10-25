#!/usr/bin/env bash
# GitHub forge: push factory/<id> and open its pull request, or update both after a rework.
# Prints the pull request's URL.
set -euo pipefail
. "$FACTORY_HOME/forges/state.sh"; . "$(dirname "$0")/lib.sh"
pushed=$(state_get pushed)
# Another machine's task: the remote has the branch, and this run never pushed it
if [ -z "$pushed" ] && git -C "$PRODUCT" ls-remote --exit-code --heads "$FORGE_REMOTE" "refs/heads/$branch" >/dev/null; then
  die "$FORGE_REMOTE already has $branch, pushed from another machine: someone else runs a task with this id. Settle who runs it; nothing pushed."
fi
# The pull request is against the remote's main: local commits on main would show up in it
git -C "$PRODUCT" fetch -q "$FORGE_REMOTE" main
ahead=$(git -C "$PRODUCT" rev-list --count "$FORGE_REMOTE/main..main")
[ "$ahead" = 0 ] || die "main has $ahead commit(s) that $FORGE_REMOTE/main doesn't; push main first, or the pull request would include them"
# Up to date with the remote's main: forges often require it, and a conflict is better found now
git -C "$wt" rebase -q "$FORGE_REMOTE/main" \
  || { git -C "$wt" rebase --abort; die "$branch conflicts with $FORGE_REMOTE/main; nothing pushed"; }
sha=$(git -C "$wt" rev-parse HEAD)
git -C "$PRODUCT" push -q --force-with-lease="refs/heads/$branch:$pushed" "$FORGE_REMOTE" "$branch:refs/heads/$branch" \
  || die "push refused: $branch on $FORGE_REMOTE isn't what this run last pushed (someone else pushed to it); nothing pushed"
state_set pushed "$sha"

# section <heading>: the markdown section of REPORT.md whose heading starts with <heading>
report="$RUNDIR/REPORT.md"; [ -f "$report" ] || report="$wt/REPORT.md"
section() {
  [ -f "$report" ] || return 0
  awk -v want="$(tr '[:upper:]' '[:lower:]' <<<"$1")" '
    /^#+[[:space:]]/ { h = tolower($0); sub(/^#+[[:space:]]*/, "", h); on = (index(h, want) == 1) }
    on' "$report"
}
body="$RUNDIR/pr-body.md"
{ [ "$(cat "$RUNDIR/verdict" 2>/dev/null)" = approve ] \
    || printf '> **The AI reviewer objects to this change** (it ended %s after your remarks): read its review at the end.\n\n' "$(cat "$RUNDIR/verdict" 2>/dev/null)"
  if [ -f "$report" ]; then cat "$report"; else echo "(no REPORT.md)"; fi
  last=$(ls "$RUNDIR"/review-[0-9]*.md 2>/dev/null | sort -V | tail -1 || true)
  [ -z "$last" ] || { printf '\n---\n\n## AI review (%s)\n\n' "$(basename "$last" .md)"; cat "$last"; }
  u=$("$FACTORY_HOME/bin/metrics" --summary "$RUNDIR")
  if [ -n "$u" ]; then printf '\n---\n\nUsage: %s\n' "$u"; fi
} > "$body"
if [ -z "$pr" ]; then
  url=$(gh pr create --base main --head "$branch" --title "factory: $id" --body-file "$body")
  state_set pr "${url##*/}"; state_set url "$url"
  state_set answered "$(ls "$RUNDIR"/user-review-*.md 2>/dev/null | wc -l || true)"   # nothing to answer on a new PR
else
  gh pr edit "$pr" --body-file "$body" >/dev/null; url=$(state_get url)
fi
# After a rework: say what was addressed, with the implementer's answers
n=$(ls "$RUNDIR"/user-review-*.md 2>/dev/null | wc -l || true)
answered=$(state_get answered); answered=${answered:-0}
if [ "$n" -gt "$answered" ]; then
  { printf 'Addressed your review in %s.\n\n' "$sha"; section "Review answers"; } > "$RUNDIR/pr-comment.md"
  gh pr comment "$(state_get pr)" --body-file "$RUNDIR/pr-comment.md" >/dev/null
  state_set answered "$n"
fi
echo "$url"
