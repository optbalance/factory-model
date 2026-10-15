#!/usr/bin/env bash
# PreToolUse hook: JSON on stdin → neutral guard. Exit 2 blocks; stderr goes to the model.
# The plugin lives in the factory, so FACTORY_HOME is known even if the shell doesn't export it.
FACTORY_HOME="${FACTORY_HOME:-$(cd "$(dirname "$(readlink -f "$0")")/../../../.." && pwd)}"; export FACTORY_HOME
[ -x "$FACTORY_HOME/guards/bash.sh" ] \
  || { echo "Blocked by factory: guards not found in $FACTORY_HOME; nothing runs unguarded" >&2; exit 2; }
in=$(cat)
case "$(jq -r .tool_name <<<"$in")" in
  Bash) exec "$FACTORY_HOME/guards/bash.sh" "$(jq -r '.tool_input.command // ""' <<<"$in")" ;;
  Edit|Write|MultiEdit|NotebookEdit)
    exec "$FACTORY_HOME/guards/files.sh" \
         "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in")" ;;
esac
exit 0
