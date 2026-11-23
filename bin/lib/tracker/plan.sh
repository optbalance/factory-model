# Sourced by bin/tracker, which has checked the arguments and set PRODUCT, TRACKER_STATE and t().
# plan <story>: runs the planner (roles/planner.md) on the story in a detached worktree of main,
# then publishes its tasks, posts its notes and moves the story to refined; or posts its questions
# and moves the story to blocked. A failed plan is posted too, and also goes to blocked, so sync
# never retries it on its own; an error before the planner starts (the tracker's API) is not
# posted, and the next sync tries again. The story moves only if it is still todo. The run dir is
# $PLAN_RUN (set by sync) or the next runs/plan-<story>/<n>; it gets `exit` when the plan ends.
story=$1
base="$FACTORY_HOME/runs/plan-${story,,}"; mkdir -p "$base"
rd=${PLAN_RUN:-"$base/$(( $(find "$base" -mindepth 1 -maxdepth 1 -type d | wc -l) + 1 ))"}
mkdir -p "$rd/plan"
wt="$PRODUCT-wt/plan-${story,,}"
trap 'echo $? > "$rd/exit"; git -C "$PRODUCT" worktree remove --force "$wt" 2>/dev/null || true' EXIT

status_of() { t items | awk -F'\t' -v k="$1" '$1 == k { print $2 }'; }
finish() {  # finish <status> <comment-file>: post the comment, then move the story if still todo
  local now
  t comment "$story" < "$2"
  now=$(status_of "$story")                        # an assignment, so a failed call stops here
  if [ "$now" = todo ]; then t move "$story" "$1"; echo "plan: $story → $1"
  else echo "plan: $story was moved meanwhile; left where it is"; fi
}
fail() {
  printf 'Planning failed: %s\n\nRun dir on the factory machine: `%s`\n' "$1" "$rd" > "$rd/comment.md"
  finish blocked "$rd/comment.md"; exit 1
}

# The prompt: the story, its current tasks, and the comments not given to a planner yet. Comments
# are kept in the tracker state until a planner has read them, so a failed run doesn't lose them.
pending="$TRACKER_STATE/$story.plan-comments.md"
t comments "$story" >> "$pending"
tasks=$(t items "$story")                          # an assignment, so a failed call stops here
{ printf 'Plan the story %s.\nOutput: %s\n\n## Story\n\n' "$story" "$rd/plan"
  t read "$story"
  first=1
  while IFS=$'\t' read -r -u 3 key status _; do
    [ -n "$key" ] && [ "$status" != canceled ] || continue
    [ $first = 0 ] || printf '\n## Current tasks\n'; first=0
    printf '\n### %s (%s)\n\n' "$key" "$status"; t read "$key"
    t comments "$key" >> "$pending"
  done 3<<<"$tasks"
  [ ! -s "$pending" ] || { printf '\n## Comments\n\n'; cat "$pending"; }
} > "$rd/brief.md"

git -C "$PRODUCT" worktree remove --force "$wt" 2>/dev/null || true
git -C "$PRODUCT" worktree add -q --detach "$wt" main || fail "creating the worktree $wt failed"
"$FACTORY_HOME/bin/agent-run" planner "$wt" "$rd/brief.md" "$rd" > "$rd/planner.log" 2>&1 \
  || fail "the planner exited with an error (\`planner.log\` in the run dir)"
rm -f "$pending"                                   # the planner has read them

if [ -f "$rd/plan/QUESTIONS.md" ]; then
  finish blocked "$rd/plan/QUESTIONS.md"
elif compgen -G "$rd/plan/*.md" > /dev/null; then
  "$FACTORY_HOME/bin/tracker" publish "$PRODUCT" "$story" "$rd/plan" > "$rd/publish.out" 2> "$rd/publish.err" \
    || fail "publishing the tasks was refused: $(cat "$rd/publish.err")"
  { echo "Planned. Tasks:"; echo
    awk -F'\t' '{ printf "- %s `%s`: %s\n", $1, $2, $3 }' "$rd/publish.out"
    [ ! -s "$rd/planner.out.md" ] || { echo; cat "$rd/planner.out.md"; }
  } > "$rd/comment.md"
  finish refined "$rd/comment.md"
else
  fail "the planner wrote neither task files nor QUESTIONS.md"
fi
