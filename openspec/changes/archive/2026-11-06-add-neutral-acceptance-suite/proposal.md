# Proposal

## Why

greeter-acceptance exists to prove that every greeterHQ channel greets the same
way, and to publish a ledger of where channels genuinely differ. Today the suite
is scaffolding only: there are no scenarios, no driver adapters, and no
traceability output. Until a real neutral suite runs against both `cli` and
`http`, nothing proves the two channels agree on shared behaviour or records
which capabilities each one lacks.

## What Changes

- Introduce a channel-neutral Cucumber suite whose features assert only two
  neutral outcomes: a guest is **greeted**, or a name is **rejected as invalid**.
  No status codes, exit codes, headers, or JSON appear in features.
- Add neutral behaviours that only capability-bearing channels can observe
  (greeting count, returning-guest count, idempotent replay), each as its own
  single-purpose scenario tagged `@capability-<name>`.
- Gate scenarios by capability with a single `Before` hook: it compares a
  scenario's `@capability-*` tags to the active driver's capabilities and marks
  the whole scenario `not_applicable` when any required capability is missing. No
  per-step guards. A startup check validates every `@capability-*` tag against
  the known capability set so a typo cannot silently turn into a failure.
- Define the `GreeterDriver` port and two black-box adapters: `CliDriver`
  (spawns `greeter <name>`; no counting, no idempotency) and `HttpDriver`
  (POST `/greetings`; capabilities `:counting`, `:idempotency`).
- Emit `tmp/traceability.json` (`greeterhq.traceability.v1`): flat per-scenario
  rows for the channel of the current run, each `not_applicable` row carrying its
  `missing_capabilities`.
- Emit a derived `tmp/ledger.json` that merges the `cli` and `http` runs into a
  requirement-by-channel matrix — the headline artifact showing the capability
  frontier.

## Capabilities

### New Capabilities
- `greeting`: the channel-neutral greeting behaviour exercised through the
  `GreeterDriver` port — greeting a guest, rejecting an invalid name, and the
  capability-gated observations (count, returning-guest count, idempotent
  replay) that distinguish channels.
- `driver-contract`: the substitutability contract every channel adapter must
  satisfy — the port method surface, capability declaration, and the neutral
  `not_applicable` behaviour drivers must exhibit for capabilities they lack.
- `traceability`: the run artifacts — per-channel `traceability.json` rows and
  the derived merged `ledger.json` matrix — including the scenario rollup rule
  (any `not_applicable` step makes the scenario `not_applicable`).

### Modified Capabilities
<!-- None. This is the first suite; no existing spec requirements change. -->

## Impact

- **Channels affected**: `cli` and `http`. Both must implement `GreeterDriver`
  and pass the driver-contract examples; `cli` records `not_applicable` for the
  capability-gated scenarios, `http` passes them.
- **New code (this repo only)**: `lib/greeter_acceptance/ports/greeter_driver.rb`,
  `lib/greeter_acceptance/drivers/cli_driver.rb` and `http_driver.rb`,
  `features/` scenarios and step definitions, `features/support/env.rb` and the
  capability hook, `spec/drivers/greeter_driver_contract.rb`, the trace/ledger
  writer, and `docs/traceability-schema.md`.
- **Non-goals**: no channel-specific outcomes in features (no 201/200/409/400/503,
  no exit codes); no `WebDriver`/`MobileDriver`/`EventDriver`; no Pact consumer
  wiring (that is Card 3); no changes to greeter-core, greeter-cli, or
  greeter-http — drivers stay black-box and talk only to a process or a URL.
- **Semver**: MINOR bump to the suite's tag — this adds the first real scenarios,
  which is additive given no consumer is yet pinned to a pre-suite tag. If a
  consumer is already pinned to an earlier port shape, treat as MAJOR; verify
  consumer `ACCEPTANCE_REF` pins before tagging. Consumers adopt by bumping
  `ACCEPTANCE_REF` to the new tag.
