# <Product name>

<One sentence: what the product does and for whom.>

## Architecture

<About 10 lines: the main parts, how a request or job flows through them, where state lives,
and which external services it talks to.>

## Layout

- `src/<area>/`: <what lives here>
- `tests/`: <unit vs. integration tests, file naming>
- `scripts/verify`: the health check (see "Definition of done")
- `docs/specs/`: specs and task files

## Commands

- Install dependencies: `<npm ci>` (needs network)
- Run locally: `<npm run dev>`
- Check everything: `scripts/verify`. While iterating: `scripts/verify --quick`.

## Definition of done

Work is done only when `scripts/verify` exits 0. Never weaken, skip or delete tests to make it
pass. If a test is wrong, say so in your report instead of changing it.

## Conventions

- <Language and framework versions; style rules the linter doesn't enforce>
- <Error handling, logging, naming>
- <How tests are written: where they live, what they mock, what they don't>

## Never touch

- <Generated or vendored code: `src/generated/`, `vendor/`>
- <Applied database migrations; add a new migration instead>
- <Public API contracts, unless the task's spec says so>

## More docs

- `<docs/architecture.md>`: <when to read it>