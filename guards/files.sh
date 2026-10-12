#!/usr/bin/env bash
# usage: files.sh "<path>"   → exit 0 = allow, exit 2 = block (reason on stderr)
# Checks a path an agent is about to write or edit, as given and with symlinks resolved. Relative
# paths are resolved against the current directory: the worktree, where the harness runs.
p="$1"
r=$(realpath -m -- "$p" 2>/dev/null || echo "$p")
block() { echo "Blocked by factory: $1" >&2; exit 2; }

for name in "${p##*/}" "${r##*/}"; do
  case "$name" in
    .env.example|.env.sample|.env.template) ;;
    .env|.env.*)
      block "don't write $p. Environment files hold secrets, and verify must not need one. Put example values in .env.example." ;;
    package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lock|bun.lockb|gradle.lockfile|*.lockfile|\
    Cargo.lock|go.sum|poetry.lock|Pipfile.lock|uv.lock|composer.lock|Gemfile.lock)
      block "don't edit $p by hand. Tasks never change dependencies: everything this task needs is already declared on main. If you need a change, stop and explain which one and why under open questions in REPORT.md." ;;
  esac
done

# harness config inside the worktree (the harness's own files under $HOME are fine)
harness='/(\.pi|\.claude|\.codex|\.agents|\.agent)/|/\.mcp\.json/$'
case "$r" in
  "$PWD"/*) [[ "/${r#"$PWD"/}/" =~ $harness ]] \
    && block "don't write harness config ($p). The factory configures the harness, and config in the worktree would change how later runs behave." ;;
esac
exit 0
