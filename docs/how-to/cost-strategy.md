# Cost Strategy: Running the Factory Cheaply

How the factory spends money on models, which levers lower that spend, and why the lowest
long-term cost comes from discipline and routing, not from buying hardware.

> Prices, plans and provider terms change often. The figures here were checked in October 2026.
> Re-check them before you rely on them, and trust your own usage logs over any estimate here.

---

## How you are billed

1. **A turn is one request to the model, not one prompt from you.** One user prompt usually
   becomes 5–50 turns: the model asks for a file, the tool runs, the result goes back, the model
   asks to run tests, and so on.
2. **Every turn re-sends the whole context.** You pay for the sum of the context sizes across all
   turns, not for how full the window ends up. A session that ends at 300k tokens has *read*
   millions of tokens.
3. **Cached input is cheap; new input and output are not.** Per million tokens on a $4/$20 frontier
   model:

   | Token type | Price | Relative to input |
   |---|---|---|
   | Cached context, re-read every turn | $0.20 | 5% |
   | New context, written to the cache | ~$5 | 1.25× (2× for the 1-hour cache) |
   | Input with no caching | $4 | 1× |
   | Output, including thinking | $20 | 5× |

4. **Cheap per token is not cheap in total.** Re-reads are 5% of the price, but you re-read millions
   of tokens, so they are often still the largest line on the bill (see the example below).
5. **The cache only helps while it holds.** It is lost when:
   - no request arrives for 5 minutes (the default lifetime), for example during a long test run.
     The next turn rewrites the whole context at the cache-write price: ~$1.50 for 300k tokens.
   - anything early in the prompt changes: system prompt, tool list, model or effort level.
     Switching a role's model in `config/routing.json` starts that role with an empty cache.
   - context editing or compaction rewrites the history.

   The cache is keyed by the exact prefix, not by session. Parallel workers with the same model,
   tools and system prompt share the cached tools and system prompt; each worker's history is its
   own. If the harness puts something per-worker into the system prompt (working directory, date),
   that sharing is lost. Check the usage fields of each run: after the first
   turn, cache-read tokens should be large. If they stay at zero, something in the prompt changes
   every turn and you are paying full price.

### Worked example

One conductor session that grows to 300k tokens over 120 turns, on a frontier model at
$4 input / $20 output / $0.20 cache read per million tokens:

| Part | Calculation | Cost |
|---|---|---|
| Re-reading cached context | ~150k average × 120 turns = 18M × $0.20/M | $3.60 |
| Writing new context to the cache | ~300k × ~$5/M | $1.50 |
| Output, including thinking | ~150k × $20/M | $3.00 |
| **Per session** | | **~$8** |
| **Without caching** | 18M × $4/M + output | **~$75** |

Four such sessions a day is about $32 a day, or roughly $670 a month on working days.

A factory task with a fresh 40k-token context and ~40 turns costs about $1 on the same model, or
about half that on a mid-tier model. **Short, well-specified tasks cost less per unit of work than
long conductor sessions.** Parallelism alone doesn't raise cost; long contexts, unlimited retries and
best-of-N do.

---

## Levers, ranked

Free wins first, trade-offs after. "Where it lives" is where you configure it in this repo.

| # | Lever | Effect | Where it lives |
|---|---|---|---|
| 1 | **Short, fresh sessions per task.** One task per session; never run sessions to 300k+ tokens | Largest. Cost per turn grows with context size | Task templates, `bin/run-task` |
| 2 | **Keep the cache warm.** Stable role prompts and tool lists, nothing that changes per run (timestamps, IDs) at the top of the prompt | Re-reads at ~5% of the input price. Broken caching costs ~10× | `roles/*.md`, the adapter |
| 3 | **Route models by role.** Strongest model only for planner and reviewer; cheapest model that passes evals for implementer and scout | 2–4× on the implementer volume | `config/routing.json` |
| 4 | **Control effort.** Thinking tokens are billed as output. Low or medium effort for routine work | Large, because output is the expensive part | Model string in `config/routing.json` (`:low`, `:medium`, …) |
| 5 | **Cut tool output.** Cap test and log output; let scripts summarize. Keep deterministic work in scripts | Medium | Guards, `scripts/verify`, wrappers |
| 6 | **Better specs, capped retries, escalation.** Fail fast on verify, retry once, then escalate to a stronger model or to a human | Rework multiplies every other cost | Task templates, `bin/run-task` |
| 7 | **Subagents for reading-heavy work.** Only the conclusion comes back into the parent context | Medium | Role prompts, the scout role |
| 8 | **Batch API for work that can wait** (see below) | 50% on that slice | A separate runner path |
| 9 | **Clear old tool results or compact** | Medium, but it breaks the cache. Measure before adopting | The harness |
| 10 | **Log cost per task** from the usage fields of every run | Makes every lever above measurable | `bin/agent-run`, the factory log |

### Effort: same price per token, different number of tokens

Effort (low, medium, high, xhigh, max) tells the model how much work to put into a request. It has
no price of its own; it changes how many tokens are used:

- **Thinking.** More effort means more thinking, and thinking is billed as output (the most
  expensive token type) even when it is hidden.
- **Turns.** More effort means more tool calls and self-checks. Each extra turn re-reads the context.
- **Time.** Longer turns can outlive the 5-minute cache.
- **Retries.** Better first attempts mean fewer failed verify runs, so on hard tasks more effort can
  cost less.

Compare **cost per completed task**, not cost per request. Set effort once per role in
`config/routing.json` and never change it mid-session: like a model change, it breaks the cache.

| Role | Starting effort |
|---|---|
| Planner | high or xhigh |
| Reviewer | high |
| Implementer | medium |
| Implementer-strong | high |
| Scout, triage | low |

These are starting points; confirm them with evals (Module 9). Defaults differ by model, and other
providers use other names (reasoning effort, thinking level). Don't confuse effort with **fast
mode**, which is the one option that does change the price per token (2× on Opus 5.5) and buys
speed, not depth.

### Hard budgets: the fix for surprise bills

A surprise bill is a control problem, not a pricing problem. Put three ceilings in place, all
outside the harness (design rule 3):

1. **Prepaid credits with auto-reload off** at each pay-per-token provider. This is the absolute
   ceiling.
2. **Per-workspace or per-key spend limits** where the provider supports them.
3. **A token budget in `bin/agent-run`.** Read usage from the harness's events, stop a run that
   exceeds its per-task budget, and refuse new runs once the daily budget is spent.

---

## Batch API

You send many independent requests as one job. The provider runs them when it has spare capacity,
within 24 hours and usually much sooner, at **50% off**. Anthropic, OpenAI and Google offer it.

It doesn't work for agent loops: each turn depends on the previous result, so every turn would wait
in the queue. Use it for single-shot work:

- reviewing finished diffs overnight
- grading evals (Module 9)
- triaging verify logs and summarizing runs

---

## Flat-fee options

The API itself is always pay-per-token. Flat-fee means a subscription with usage quotas. The quota
also acts as a natural spending cap.

| Option | Price / month | Usable from Pi? | Catch |
|---|---|---|---|
| Claude Pro / Max 5x / Max 20x | $20 / $100 / $200 | **No.** Since February 2026, Anthropic's terms allow subscription logins only in Claude Code and claude.ai. Pi's `/login` still offers it, but using it breaks the terms | Legitimate only through a **Claude Code adapter**. Heavy automated use hits the quotas |
| ChatGPT Plus/Pro (Codex), GitHub Copilot | varies | Pi supports `/login` for both | Check each provider's current terms on third-party tools |
| Coding plans: Z.ai GLM, MiniMax, Alibaba Qwen, Kimi | ~$10–50 | Through an OpenAI- or Anthropic-compatible endpoint, as a custom provider | Quotas in prompts per 5 hours. Servers in China. Supported-tool lists may not include Pi. Quotas and terms change often |

The coding plans give access to the strongest open-weight models (GLM-5, Kimi K2.5, Qwen 3.7,
MiniMax M2.5 class), which would need €10k+ of hardware to run locally.

---

## Local models: the verdict

Running models on your own hardware only makes sense for privacy, offline work or learning. On cost
alone it loses:

| Option | Price | Best model it runs | Monthly cost (36-month write-off + power) |
|---|---|---|---|
| Current laptop (i7-1165G7, 32 GB, no GPU) | €0 | 20–30B MoE at 8–12 tok/s | ~€3. Too slow for agent work; fine for triage experiments |
| Ryzen AI Max+ 395 mini PC, 128 GB | ~€2,300–3,500 | ~100B MoE (gpt-oss-120b, GLM-Air class) | ~€70–125 |
| Mac Studio M3 Ultra, 256 GB | ~€8–10k | ~230B MoE at 4-bit | ~€240–320 |
| 512 GB+ for full DeepSeek, Kimi or GLM | €15–40k+ (Apple dropped its 512 GB option in March 2026) | best open-weight models | ~€500–1,100+ |

Why it loses:

- **Quality ceiling.** Affordable hardware gives cheap-tier quality. Planner and reviewer stay on
  frontier APIs anyway, so local only replaces part of the implementer spend.
- **Throughput.** One box runs about one agent at a time, several times slower than an API. Parallel
  workers become one slow queue.
- **Hosted alternatives.** The same open-weight models are sold through APIs and coding plans for
  about what the box costs per month, with no hardware to buy or maintain.
- **Electricity is not the issue.** At ~€0.24/kWh in Spain (PVPC plus taxes), even 24/7 operation
  of a mini PC costs ~€26 a month. Hardware price and quality are what matter.
- **Timing.** DRAM shortages have inflated memory-heavy hardware prices in 2026.

---

## Recommended setup

| Role | Model source | Cost control |
|---|---|---|
| Planner | Frontier model via API key | Prepaid credits, budget in `bin/agent-run` |
| Reviewer | Frontier model from a **different family** than the implementer, via API | Batch API where it can wait |
| Implementer | Flat coding plan (GLM, Qwen or MiniMax); escalate failures to a mid-tier API model | Flat fee plus quota |
| Scout | Cheap tier of the coding plan, or a small API model | Flat fee or low per-token cost |
| Local | None | — |

Rough target: **$150–300 a month with a hard ceiling**, versus an open-ended $400–900. Confirm with
your own evals (Module 9): whether the coding-plan models pass verify often enough is an empirical
question. Keep an API fallback configured in `config/routing.json`, because coding-plan quotas and
terms change without much notice.

---

## Checklist

- [ ] Prepaid credits, auto-reload off, at every pay-per-token provider
- [ ] Per-task and daily token budgets enforced in `bin/agent-run`
- [ ] Cost per task logged from usage fields
- [ ] Role prompts stable; nothing per-run at the top of the prompt
- [ ] `config/routing.json` uses the strongest model only for planner and reviewer
- [ ] Effort set per role
- [ ] Retries capped, with escalation
- [ ] Test and log output truncated before it reaches the model
- [ ] Reviews and evals that can wait go through the Batch API
- [ ] Coding-plan provider configured, with an API fallback
