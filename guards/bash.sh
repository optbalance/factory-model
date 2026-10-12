#!/usr/bin/env bash
# usage: bash.sh "<command>"   → exit 0 = allow, exit 2 = block (reason on stderr)
# Each reason is written for the model: what is blocked, and what to do instead.
cmd="$1"
block() { echo "Blocked by factory: $1" >&2; exit 2; }

# git push, also with options before the subcommand (git -C <dir> push)
if grep -Eq '(^|[^[:alnum:]_./-])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+push\b' <<<"$cmd"; then
  block "don't push. The runner commits your work after verify passes, and a human merges it. Leave your changes in the worktree."
fi
# a download piped into a shell
if grep -Eq '\b(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh\b' <<<"$cmd"; then
  block "don't pipe a download into a shell. Tasks never install tools or dependencies: if one is missing, stop and say so under open questions in REPORT.md."
fi
# recursive delete of / or the home directory (paths inside the worktree are fine)
if grep -Eq '\brm[[:space:]]+([^;&|]*[[:space:]])?(-[[:alpha:]]*[rR][[:alpha:]]*|--recursive)\b[^;&|]*[[:space:]](/|~|\$HOME|\$\{HOME\})/?\*?([[:space:];&|]|$)' <<<"$cmd"; then
  block "don't delete / or the home directory. Delete only paths inside the worktree."
fi
exit 0
