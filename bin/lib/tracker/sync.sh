# Sourced by bin/tracker, which has checked the arguments and set PRODUCT, TRACKER_STATE and t().
# sync: one pass over the board (Module 11, item 5), under a lock per product. Plans, batches and
# reworks run in the background, detached, so a pass takes seconds; the next pass sees how they
# ended.
# State in $TRACKER_STATE/<key>: `plan` (a story's latest plan run dir) and `run` (a task's latest
# run dir); runs/<timestamp>.exit holds a batch's fan-out exit code once it ends. A plan or batch
# that died without finishing (a reboot) is started again: its lock tells (bin/lib/lock.sh).
[ -n "${FACTORY_STARTED:-}" ] || die "start it through bin/start (bin/start bin/tracker sync <product-dir>): the reworks it starts need the secrets"
exec 9> "$TRACKER_STATE/sync.lock"
flock -n 9 || { echo "sync: another sync of this product is running"; exit 0; }
MAX_RUNNING=3

. "$FACTORY_HOME/bin/lib/lock.sh"
say() { echo "$(date '+%F %T') sync: $*"; }          # dated: a timer appends passes to one log
# detach <lock-file> <log> <command...>: runs it in the background, in its own session, holding
# the lock on <lock-file> (taken here, before it starts) until it and its children end
detach() {
  local lock=$1 log=$2; shift 2
  exec 7> "$lock"; flock 7
  setsid "$@" < /dev/null > "$log" 2>&1 9>&- &
  exec 7>&-
}
move() { t move "$1" "$2" && say "$1 → $2"; }       # move <key> <status>
note() { t comment "$1"; }                         # note <key> < markdown
# merged <id>: main has the task's commit (decided by git, not by the task's status). No grep -q:
# it would stop reading early, and git's failed write would count under pipefail.
merged() { git -C "$PRODUCT" log --format=%s main | grep -E "^factory: ${1//./\\.}( |$)" > /dev/null; }
list() { local x; IFS=, read -ra L <<<"$1"; for x in "${L[@]}"; do x=${x//[[:space:]]/}; x=${x#./}; x=${x%/}; [ -z "$x" ] || echo "$x"; done; }
# overlaps <touches> <touches>: a path in one is a path in the other, or a directory holding it.
# A task without touches overlaps everything.
overlaps() {
  local a b A B; mapfile -t A < <(list "$1"); mapfile -t B < <(list "$2")
  [ ${#A[@]} -gt 0 ] && [ ${#B[@]} -gt 0 ] || return 0
  for a in "${A[@]}"; do for b in "${B[@]}"; do
    [ "$a" = "$b" ] || [[ $a == "$b"/* ]] || [[ $b == "$a"/* ]] && return 0
  done; done; return 1
}

# 1. The forge: reworks, merges (main updated and verified), closed reviews. A failure here, or a
# red main, means no new batch this pass.
main_ok=1
[ -z "$(git -C "$PRODUCT" for-each-ref 'refs/heads/factory/*')" ] \
  || REWORK_DETACH=1 "$FACTORY_HOME/bin/review" sync "$PRODUCT" 9>&- || main_ok=0

stories=$(t items)                                 # an assignment, so a failed call stops here
declare -A sstatus skey                           # skey: a story's key by its lowercased key (depends_on)
while IFS=$'\t' read -r -u 3 key status _; do
  [ -n "$key" ] || continue; sstatus[$key]=$status; skey[${key,,}]=$key
done 3<<<"$stories"

# 2. Each started task: where its run stands, and the status that goes with it.
phase() {  # phase <task-run-dir>
  local rd=$1
  if merged "$(basename "$rd")"; then echo done
  elif run_alive "$rd"; then echo in-progress
  elif [ ! -f "$rd/status" ]; then
    if rework_interrupted "$rd"; then echo wait            # bin/review sync runs it again
    elif lock_held "$(dirname "$rd").lock"; then echo in-progress   # the batch is starting it
    elif [ -f "$(dirname "$rd").exit" ]; then echo failed  # the batch ended without a result for it
    else echo died; fi                                 # the batch died (a reboot): run it again
  else
    case $("$FACTORY_HOME/bin/forge" status "$PRODUCT" "$rd" 2>/dev/null || echo error) in
      pending|approved) echo in-review ;;
      changes-requested|error) echo wait ;;         # the rework is starting (bin/review sync); or ask again next pass
      closed) echo closed ;;
      *) echo red ;;                                # not submitted: red, or the AI reviewer objects
    esac
  fi
}
declare -A tstatus tstory trun
for s in "${!sstatus[@]}"; do
  [ "${sstatus[$s]}" = in-progress ] || continue
  tasks=$(t items "$s")
  while IFS=$'\t' read -r -u 3 key status _; do
    [ -n "$key" ] || continue
    tstatus[$key]=$status; tstory[$key]=$s; trun[$key]=$(kv_get "$TRACKER_STATE/$key" run)
    rd=${trun[$key]}
    case "$status" in in-progress|in-review) [ -n "$rd" ] || continue ;; *) continue ;; esac
    want=$(phase "$rd")
    [ "$want" != "$status" ] && [ "$want" != wait ] || continue
    case "$want" in
      done)        move "$key" done ;;
      in-progress) printf 'Rework started on your review remarks.\n' | note "$key"; move "$key" in-progress ;;
      in-review)   url=$(kv_get "$rd/forge-state" url)          # none on the local forge
                   printf 'Ready for your review: %s\n' "${url:-run \`bin/start bin/review\` in the product repo}" | note "$key"
                   move "$key" in-review; want=in-review ;;
      failed)      { echo 'The batch ended without running this task. The end of its log:'; echo; echo '```'
                     tail -20 "$(dirname "$rd").log"; echo '```'; } | note "$key"
                   move "$key" blocked; want=blocked ;;
      closed)      printf 'The review was closed without a merge. Edit the task or comment, then move it to todo to run it again from main.\n' | note "$key"
                   move "$key" blocked; want=blocked ;;
      died)        say "$key: its run stopped without finishing; it runs again"
                   want=restart ;;                  # step 5 starts it again; its status stays in-progress
      red)         { echo 'Not ready for review. Edit the task or comment, then move it to todo to run it again from main.'; echo; echo '```'
                     "$FACTORY_HOME/bin/collect" "$rd"; echo '```'; } | note "$key"
                   move "$key" blocked; want=blocked ;;
    esac
    tstatus[$key]=$want
  done 3<<<"$tasks"
done

# 3. Each story in todo: plan it in the background, unless a plan runs already or its tasks have
# started (a re-plan would cancel them). The plan moves the story itself (bin/lib/tracker/plan.sh).
while IFS=$'\t' read -r -u 3 key status _; do
  [ "$status" = todo ] || continue
  rd=$(kv_get "$TRACKER_STATE/$key" plan)
  if [ -n "$rd" ] && [ ! -f "$rd/exit" ]; then
    lock_held "$rd/running.lock" && { say "$key: planning"; continue; }
    say "$key: its plan stopped without finishing; planning again"
  fi
  tasks=$(t items "$key")
  if grep -qE $'\t(in-progress|in-review|done)\t' <<<"$tasks"; then
    say "$key: in todo, but its tasks have started; not planned again (move it back to in-progress)"; continue
  fi
  base="$FACTORY_HOME/runs/plan-${key,,}"; mkdir -p "$base"
  rd="$base/$(( $(find "$base" -mindepth 1 -maxdepth 1 -type d | wc -l) + 1 ))"; mkdir "$rd"
  kv_set "$TRACKER_STATE/$key" plan "$rd"
  PLAN_RUN=$rd detach "$rd/running.lock" "$rd/plan.log" "$FACTORY_HOME/bin/tracker" plan "$PRODUCT" "$key"
  say "$key: planning started, $rd"
done 3<<<"$stories"

# 4 and 5. Each story in in-progress: start the tasks that can run, up to MAX_RUNNING for the
# product. A task can run when its depends_on are merged (or are stories that are done), and its
# touches overlap no running task's, nor one started now. A task in todo with a branch or worktree
# was blocked and moved back by you: bin/cleanup first (its work goes to abandoned.patch).
running=0; busy=()                                 # touches of tasks not merged yet
for key in "${!tstatus[@]}"; do
  case "${tstatus[$key]}" in in-progress|in-review) ;; *) continue ;; esac
  [ "${tstatus[$key]}" = in-progress ] && running=$((running + 1))
  rd=${trun[$key]}; [ -n "$rd" ] && [ -f "$rd.md" ] && busy+=("$(task_field touches < "$rd.md")") || busy+=("")
done
deps_ok() {
  local d; while read -r d; do
    if [ -n "${skey[${d,,}]:-}" ]; then [ "${sstatus[${skey[${d,,}]}]}" = done ] || return 1
    else merged "$d" || return 1; fi
  done < <(list "$1")
}
if [ $main_ok = 0 ]; then
  say "no new tasks started: bin/review sync failed, or main is red (see above)"
else
  RUN="$FACTORY_HOME/runs/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$TRACKER_STATE/tasks"; started=()
  for key in $(for k in "${!tstatus[@]}"; do case "${tstatus[$k]}" in todo|restart) echo "$k" ;; esac; done | sort -V); do
    [ $running -lt $MAX_RUNNING ] || { say "$MAX_RUNNING tasks running; the rest wait"; break; }
    body=$(t read "$key"); id=$(task_field id <<<"$body")
    [[ $id =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { say "$key: no valid id: line, not run"; continue; }
    if merged "$id"; then say "$key: $id is merged already, but the task is in todo; left alone"; continue; fi
    deps_ok "$(task_field depends_on <<<"$body")" || continue
    touches=$(task_field touches <<<"$body"); clash=0
    for b in "${busy[@]}"; do overlaps "$touches" "$b" && { clash=1; break; }; done
    [ $clash = 0 ] || continue
    if git -C "$PRODUCT" show-ref -q --verify "refs/heads/factory/$id" || [ -e "$PRODUCT-wt/$id" ]; then
      "$FACTORY_HOME/bin/cleanup" "$PRODUCT" "$id" || { say "$key: cleaning up the earlier attempt failed, not run"; continue; }
    fi
    f="$TRACKER_STATE/tasks/$id.md"
    { printf '%s\n' "$body"; c=$(t comments "$key"); [ -z "$c" ] || printf '\n## Comments from the user\n\n%s\n' "$c"; } > "$f"
    kv_set "$TRACKER_STATE/$key" run "$RUN/$id"
    if [ "${tstatus[$key]}" = restart ]; then
      printf 'The run stopped without finishing (the factory machine restarted?); it runs again from main.\n' | note "$key"
    else move "$key" in-progress || { say "$key: moving it failed, not run"; continue; }; fi
    started+=("$f"); busy+=("$touches"); running=$((running + 1)); tstatus[$key]=in-progress
  done
  if [ ${#started[@]} -gt 0 ]; then
    FANOUT_RUN=$RUN detach "$RUN.lock" "$RUN.log" bash -c '"$@"; echo $? > "$FANOUT_RUN.exit"' fan-out \
      "$FACTORY_HOME/bin/fan-out" "$PRODUCT" "${started[@]}"
    say "started ${#started[@]} task(s), $RUN"
  fi
fi

# 6. Each story in in-progress whose tasks are all done or canceled: done.
for s in "${!sstatus[@]}"; do
  [ "${sstatus[$s]}" = in-progress ] || continue
  n=0; open=0
  for key in "${!tstory[@]}"; do
    [ "${tstory[$key]}" = "$s" ] || continue
    n=$((n + 1)); case "${tstatus[$key]}" in done|canceled) ;; *) open=1 ;; esac
  done
  [ $n -gt 0 ] && [ $open = 0 ] && move "$s" done
done
exit 0
