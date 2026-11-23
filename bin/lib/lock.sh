# Sourced. Whether a background run is alive: whoever starts it takes an flock on its lock file
# before starting it, and the run inherits the lock, so it is held exactly as long as the run or
# any of its children live. The kernel drops it when they die, reboot included, so a dead run
# never looks alive. Lock files: <task-run-dir>/running.lock (fan-out, bin/rework),
# runs/<timestamp>.lock (a batch started by bin/tracker sync), <plan-run-dir>/running.lock.
# lock_held <file>: someone holds the lock. A missing file is a run that never started.
lock_held() { [ -f "$1" ] && ! flock -n "$1" true; }
# run_alive <task-run-dir>: the task's first run or a rework is running.
run_alive() { lock_held "$1/running.lock"; }
# rework_interrupted <task-run-dir>: a rework died before it finished (it removes `status` when it
# starts, and writes it at the end); bin/rework --resume runs it again with the same remarks.
# Only for someone who doesn't hold the lock: the holder's own check would see it held.
rework_interrupted() {
  [ ! -f "$1/status" ] && ls "$1"/user-review-*.md > /dev/null 2>&1 && ! run_alive "$1"
}
