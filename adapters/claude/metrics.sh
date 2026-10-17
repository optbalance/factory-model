#!/usr/bin/env bash
# usage: metrics.sh <events-file>
# One tab-separated row per call, in call order (adapter contract, Step 6):
#   turns  duration_s  tokens_in  tokens_out  tokens_cached  cost_usd  error(0|1)
# Claude Code ends every call with a `result` event. A call that continues a session reports the
# session's totals, earlier calls included (Claude Code 2.1.277+), so a result in the same session
# as the previous one has that one's totals subtracted. Tokens come from modelUsage, which also
# counts subagents; tokens_in includes cache writes.
set -euo pipefail
jq -Rrn '
  def tot: { cost:   (.total_cost_usd // 0),
             in:     ([.modelUsage[]? | (.inputTokens // 0) + (.cacheCreationInputTokens // 0)] | add // 0),
             out:    ([.modelUsage[]? | .outputTokens // 0] | add // 0),
             cached: ([.modelUsage[]? | .cacheReadInputTokens // 0] | add // 0) };
  reduce (inputs | fromjson? | select(.type? == "result")) as $e ({rows: [], prev: null};
    ($e | tot) as $t
    | (if .prev != null and .prev.sid == $e.session_id and $t.cost >= .prev.t.cost
       then .prev.t else {cost: 0, in: 0, out: 0, cached: 0} end) as $b
    | .rows += [[ ($e.num_turns // 0), (($e.duration_ms // 0) / 1000 | floor),
                  ($t.in - $b.in), ($t.out - $b.out), ($t.cached - $b.cached),
                  ($t.cost - $b.cost), (if $e.is_error then 1 else 0 end) ]]
    | .prev = {sid: $e.session_id, t: $t})
  | .rows[] | @tsv' "$1"
