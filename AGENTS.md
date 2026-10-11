# factory-model

This repo is the factory: the process that builds products, not a product itself. It is used for
any product, with any harness. Read `docs/how-the-factory-works.md` for the big picture and
`docs/building-the-factory.md` for the details.

## Strict rules

1. **No product knowledge.** This repo holds only *how* work is done. Never add anything specific
   to one product: its name, domain, code, stack, toolchain, dependencies or config. That belongs
   in the product repo (its `AGENTS.md`, `scripts/verify`, `toolchain.Containerfile`).
2. **Harness-agnostic outside `adapters/`.** Everything specific to one harness (CLI flags,
   config and hook formats, install steps, auth variables, session handling) lives only in
   `adapters/<harness>/`. Code outside `adapters/` must work unchanged with every harness.

Allowed exceptions: `config/` names harnesses, models and provider keys (choosing them is its
job), `docs/` describes products and harnesses as examples, and `templates/` holds generic
starting points for new products.

If a change can't be made without breaking a rule, stop and ask. Don't work around the rule.
