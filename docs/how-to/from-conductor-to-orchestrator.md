# From Conductor to Orchestrator

A learning path for agentic engineering, from the basics to confident orchestration.

**Conductor** means you work with one agent at a time, in real time, and steer every step. **Orchestrator** means you run several agents at once. You define the work, hand it out, check the results and improve the system that produces them. The **factory model** is where that leads: you stop building each feature yourself and build the "factory" that builds them.

---

## Level 0: How the model works

1. **LLM (large language model).** It predicts the next token based on everything in its context. It has no memory between calls. Everything it "knows" about your task has to be in the context.
2. **Token.** The unit of text a model reads and writes, roughly ¾ of a word. It's how cost, speed and limits are measured.
3. **Context window.** The model's working memory for one session. It holds the instructions, files, tool outputs and conversation. It is finite, and it is **the scarcest resource you manage**.
4. **Non-determinism.** The same input can give different outputs. Plan for variation instead of expecting the same result every time.
5. **Hallucination.** Confident output that is wrong, such as an API that doesn't exist or a claim that "tests pass" when they don't. This is why *verification* is a core idea in everything below.
6. **System prompt and instructions.** Standing guidance that shapes all of the model's behavior. Specific, clear instructions beat clever wording.

## Level 1: What an agent is

7. **Agent = model + tools + loop.** The model decides on an action, a tool runs it, the result goes back into the context, and this repeats until the task is done.
8. **Tool use (function calling).** The model makes structured calls such as read a file, run a command or search. Tools let an agent act instead of only talking.
9. **The agentic loop.** *Gather context → act → verify → repeat.* A good agent spends a lot of its effort on the first and last steps.
10. **Harness.** The runtime around the model, such as Claude Code. It handles tools, permissions, memory files and context management.
11. **Autonomy and permissions.** How much the agent may do without asking you. Autonomy should grow only as your ability to verify its work grows.
12. **Sandbox and blast radius.** Limit what an agent *can* damage: file system scope, network, credentials, whether it can push. Set containment before you add speed.

## Level 2: Context engineering, the core skill

13. **Context engineering.** Choosing *what* goes into the context and *when*. Most agent failures are context failures, not model failures.
14. **Context rot.** Quality drops as the context fills with stale or irrelevant material. Long sessions get worse over time.
15. **Persistent memory files** (such as `CLAUDE.md`). Project conventions, commands and gotchas that load into every session. This is the "onboarding doc" for your agents.
16. **Progressive disclosure and just-in-time retrieval.** Give the agent pointers ("tests live in X, run with Y"), not dumps. Let it pull detail when it needs it.
17. **Compaction and fresh sessions.** Summarize the context, or start clean, between distinct tasks. One task per session is a good default.
18. **Cold start.** Every new agent knows nothing about your conversation. What you write in its brief is all it has.

## Level 3: Conducting well with a single agent

19. **Spec first.** Write down the goal, constraints, acceptance criteria and what's out of scope before any code. A vague spec gives vague code, faster.
20. **Plan, then execute.** Have the agent propose a plan, review it, then let it implement. Fixing a plan is cheap. Fixing code is expensive.
21. **Verifiable tasks.** Size tasks so that success can be checked by a test, a type check, a build or a screenshot. *If the agent can't verify it, you'll have to.*
22. **Feedback loops.** Tests, linters, compilers and CI are the agent's senses. The stronger the automated feedback, the more autonomy you can safely give.
23. **Checkpoints.** Commit often and use git as your undo button. Cheap rollback makes experimenting safe.
24. **Course-correct early.** Interrupt as soon as you see drift. Don't wait for a finished but wrong result.
25. **Review diffs, not claims.** Judge the agent on the evidence it produces (diffs, test output), not on its summary.

## Level 4: Extending the agent

26. **Commands and skills.** Reusable, packaged workflows ("how we do a release", "how we write a migration"). They turn tacit knowledge into something agents can follow.
27. **Hooks.** Deterministic scripts that run on agent events, such as formatting on every edit or blocking writes to `prod/`. **Rule: if something must always happen, don't ask the model. Enforce it with a hook.**
28. **MCP (Model Context Protocol).** A standard way to connect agents to outside systems such as issue trackers, databases and docs.
29. **Subagents.** Child agents with their own clean context. They do focused work, such as searching, reviewing or researching, and return only the conclusion. This keeps the parent's context clean.
30. **Deterministic vs. judgment work.** Scripts handle anything with a fixed right answer. Agents handle anything that needs judgment. Mixing them up causes both flaky results and wasted tokens.

## Level 5: The shift to orchestration

31. **Delegation.** Handing a task to an agent you won't watch. It needs a **self-contained brief**: goal, context, constraints, definition of done and the output format.
32. **Task decomposition.** Split work into units that are independent, can each be checked, and each fit in one context. This is the orchestrator's main skill.
33. **Isolation.** Each parallel agent gets its own workspace, such as a **git worktree**, branch or container, so agents don't overwrite each other.
34. **Async and background agents.** Agents that run while you do something else, including headless/CLI runs (`claude -p`), cloud sessions and scheduled jobs.
35. **Handoff artifacts.** Agents communicate through durable outputs: plans, specs, PRs and reports, not through shared chat.
36. **Your bottleneck moves.** Once agents write code faster than you can review it, **your review and verification capacity sets the limit**. Invest there.

## Level 6: Orchestration patterns

37. **Orchestrator–worker.** One lead agent breaks down the task, sends out workers and combines their results.
38. **Fan-out / fan-in (map-reduce).** Run the same operation over many independent items in parallel, such as migrating 40 modules, then merge the results.
39. **Pipeline.** Specialized stages in sequence: spec → plan → implement → test → review.
40. **Generator–critic (evaluator–optimizer).** One agent produces the work and another checks it against criteria, repeating until it passes. Critics work best with fresh context and adversarial instructions.
41. **Best-of-N.** Run several attempts at a hard problem and pick or merge the best. You trade tokens for quality.
42. **Human-in-the-loop gates.** Explicit points where you approve before anything irreversible or outward-facing happens, such as a merge, deploy or published message.
43. **Trust calibration.** Match how autonomous a task is to its risk and to how well it can be verified. Low risk with strong tests can run unattended. High risk with weak tests needs you watching.

## Level 7: The factory model

44. **Build the system that builds the product.** Your output is the pipeline: specs, agents, skills, hooks, CI gates and review flow.
45. **Every failure becomes a factory improvement.** When an agent gets something wrong, fix the *system*, not only the output. Add a memory rule, a test, a hook or a skill. The factory should get better each week.
46. **Quality gates as the source of truth.** CI, tests and automated review decide whether work is "done", not how confident an agent sounds.
47. **Evals for your agents.** A set of benchmark tasks to check whether a prompt, skill or model change made your factory better or worse.
48. **Observability.** Track transcripts, token cost, success rate, time to merge and rework rate. You can't improve a factory you can't measure.
49. **Economics.** Weigh parallelism and best-of-N against their cost. Use smaller models for simple work and the strongest models for planning and review.
50. **Security at scale.** Least privilege, handling prompt injection from untrusted input (web pages, issues, dependencies), secrets kept out of context, and audit trails.

---

## The principles in one line each

- **Context is the scarcest resource.** Curate it.
- **Verification sets the ceiling on autonomy.**
- **Enforce hard rules deterministically.** Use prompts for judgment.
- **Decompose, isolate, parallelize, then integrate.**
- **Briefs are the whole world for a cold-start agent.**
- **Review the evidence, not the narrative.**
- **Improve the factory, not only the output.**

## Suggested practice order

1. Use one agent on real tasks with the **spec → plan → implement → verify** cycle (Levels 0–3).
2. Write a `CLAUDE.md` and one skill and one hook for this repo (Level 4).
3. Run two agents in parallel worktrees on independent tasks (Level 5).
4. Add a generator–critic review step (Level 6).
5. Start a log of failures and turn each one into a factory improvement (Level 7).
