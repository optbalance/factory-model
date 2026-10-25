# factory-model

This repo is the factory: the process that builds products, not a product itself. It is used for
any product, with any harness. Read `docs/how-to/how-the-factory-works.md` for the big picture and
`docs/how-to/building-the-factory.md` for the details. What a product must provide is in
`docs/product/product-contract.md`; what the machine must provide is in
`docs/factory/factory-contract.md`, what a harness adapter must provide is in
`docs/adapter/adapter-contract.md`, what a forge (git host) must provide is in
`docs/forge/forge-contract.md`, and how to run the factory is in
`docs/factory/operating-the-factory.md`.

## Strict rules

1. **No product knowledge.** This repo holds only *how* work is done. Never add anything specific
   to one product: its name, domain, code, stack, toolchain, dependencies or config. That belongs
   in the product repo (its `AGENTS.md`, `scripts/verify`, `toolchain.Containerfile`).
2. **Harness-agnostic outside `adapters/`.** Everything specific to one harness (CLI flags,
   config and hook formats, install steps, auth variables, session handling) lives only in
   `adapters/<harness>/`. Code outside `adapters/` must work unchanged with every harness. The
   same holds for forges: everything specific to one git host (its CLI, API, URLs) lives only in
   `forges/<forge>/`.

Allowed exceptions: `config/` names harnesses, models and provider keys (choosing them is its
job), `docs/` describes products and harnesses as examples, and `templates/` holds generic
starting points for new products.

If a change can't be made without breaking a rule, stop and ask. Don't work around the rule.

## Known issues: `docs/todo.md`

`docs/todo.md` lists known issues and missing features that are postponed on purpose.

- Before raising an issue, check `docs/todo.md`. If it's already listed, don't raise it again.
  Mention it only if your current work makes it worse or depends on it.
- When the user asks to postpone an issue, add it to `docs/todo.md` as one bullet a cold-start
  agent can act on: what's wrong, where (files), what goes wrong because of it, and a possible fix
  if known.
- Escalate instead of postponing when the issue can't wait: it blocks the current task, or breaks
  the verify gate, isolation, security or data. Say why it can't be postponed.
- When you fix a listed issue, remove its bullet.
