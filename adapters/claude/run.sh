#!/usr/bin/env bash
set -euo pipefail
cfg=$1; role=$2; workdir=$3; prompt=$4; rundir=$5
model=$(jq -r .model <<<"$cfg")
effort=$(jq -r '.effort // "medium"' <<<"$cfg")
tools=$(jq -r '.tools // "Read,Grep,Glob,Bash,Edit,Write"' <<<"$cfg")
budget=$(jq -r '.budget_usd // empty' <<<"$cfg")
output=$(jq -r '.output // "events"' <<<"$cfg")

export CLAUDE_CONFIG_DIR="$rundir/claude/$role"   # sessions per role (for --continue); no host config
export DISABLE_AUTOUPDATER=1
args=(-p --model "$model" --effort "$effort" --tools "$tools"
      --permission-mode bypassPermissions          # bin/sandbox is the boundary; hooks still run
      --setting-sources user                       # ignore .claude/, CLAUDE.md, AGENTS.md in the worktree
      --strict-mcp-config                          # ignore .mcp.json in the worktree
      --plugin-dir "$FACTORY_HOME/adapters/claude/plugin"   # guards + skills, same every run
      --append-system-prompt-file "$rundir/$role.system.md")   # AGENTS.md from main + role
[ -n "$budget" ] && args+=(--max-budget-usd "$budget")
[ -n "${CONTINUE:-}" ] && args+=(--continue)

cd "$workdir"
if [ "$output" = text ]; then
  # json, not text: the final answer goes to $role.out.md, the result (usage, cost) to the events log
  claude "${args[@]}" --output-format json < "$prompt" > "$rundir/$role.result.json"
  jq -c . "$rundir/$role.result.json" >> "$rundir/$role.events.jsonl"
  jq -r '.result // empty' "$rundir/$role.result.json" > "$rundir/$role.out.md"
else
  claude "${args[@]}" --output-format stream-json --verbose < "$prompt" >> "$rundir/$role.events.jsonl"
fi