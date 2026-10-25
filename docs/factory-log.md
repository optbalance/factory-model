# Factory log

One line for each time something went wrong in a run: a task that went red, ended
`changes-needed` or `error`, was re-queued, needed the user, or was approved with a real gap.
The `orchestrate` skill appends lines; the `retro` skill finds their causes and fixes them.
This file is in the factory, so it names no product's domain, code or stack: describe the failure
in factory terms and point to the run dir for the details.

Format, one line each, newest last:

```
YYYY-MM-DD | <task id> | <role>=<harness>/<model> | <what went wrong> | cause: <root cause> | fix: <file and change>, or pending, or none: <why>
```

Example:

```
2026-10-03 | 012-csv-export | implementer=claude/sonnet | edited unrelated files | cause: task Context too vague | fix: plan skill now requires explicit `touches`
```

## Log

2026-10-17 | 003-zip-csv-data-source | reviewer=claude/opus | approved although two acceptance criteria aren't tested and one spec rule is broken; it listed them only as minor (runs/20261017-152937/003-zip-csv-data-source/review-1.md) | cause: reviewer role doesn't say an untested or unmet acceptance criterion is a finding | fix: pending
2026-10-17 | 006-backtest-recorder | reviewer=claude/opus | approved with a real gap that it left to a later task (007), whose task file doesn't mention it (runs/20261017-152937/006-backtest-recorder/review-1.md) | cause: no step carries a reviewer's "a later task must handle this" into that task file | fix: pending
2026-10-23 | 004-replay-hub | implementer=claude/sonnet, reviewer=claude/opus | both harness calls failed authentication at turn 1; empty diff was still reported green (verify ran on unchanged main), only the review showed error (runs/20261023-210452/004-replay-hub) | cause: orchestrator session not started via bin/start, so CLAUDE_CODE_OAUTH_TOKEN was unset in the sandbox; fan-out only warns, and run-task doesn't treat a failed implementer call / empty diff as red | fix: pending
2026-10-23 | 005-trader-assembly | implementer=claude/sonnet, reviewer=claude/opus | same as 004-replay-hub: authentication failed, empty diff reported green / error (runs/20261023-210452/005-trader-assembly) | cause: same missing CLAUDE_CODE_OAUTH_TOKEN | fix: pending
