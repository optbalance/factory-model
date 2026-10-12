#!/usr/bin/env bash
# PreToolUse hook: JSON on stdin → neutral guard. Exit 2 blocks; stderr goes to the model.
in=$(cat)
case "$(jq -r .tool_name <<<"$in")" in
  Bash) exec "$FACTORY_HOME/guards/bash.sh" "$(jq -r '.tool_input.command // ""' <<<"$in")" ;;
  Edit|Write|MultiEdit|NotebookEdit)
    exec "$FACTORY_HOME/guards/files.sh" \
         "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in")" ;;
esac
exit 0
