# greeter-acceptance

[![CI](https://github.com/greeterhq/greeter-acceptance/actions/workflows/ci.yml/badge.svg)](https://github.com/greeterhq/greeter-acceptance/actions/workflows/ci.yml)

The channel-neutral acceptance suite for greeterHQ. One set of Cucumber features
describes greeting behaviour once; a `GreeterDriver` port and one black-box
driver adapter per channel translate that behaviour into each channel's idiom.
The suite proves that every channel greets the same way, and publishes a ledger
of where channels genuinely differ.

## What it does

The features assert only two channel-neutral outcomes — a guest is **greeted**,
or a name is **rejected as invalid**. Behaviours that only some channels can
observe (greeting count, returning-guest count, idempotent replay) are each
their own scenario, tagged `@capability-<name>`. A channel that lacks a required
capability records the scenario as **not applicable** — never failed or skipped.

Every run writes a per-channel `tmp/traceability.json` (schema
`greeterhq.traceability.v1`); merging the per-channel files produces
`tmp/ledger.json`, the requirement-by-channel matrix that is the suite's headline
artifact:

```
requirement           cli              http
greeting-happy        passed           passed
greeting-invalid      passed           passed
greeting-count        not_applicable   passed
greeting-returning    not_applicable   passed
greeting-idempotent   not_applicable   passed
```

See `docs/traceability-schema.md` for the full trace and ledger schemas.

## Architecture

Hexagonal. Step definitions talk to one port; drivers are black-box and talk
only to a process or a URL — they never require `greeter-core`, `greeter-cli`, or
`greeter-http` code.

```
features/
  greeting.feature            behaviour, written once, channel-neutral
  step_definitions/           call ONLY the GreeterDriver port
  support/
    env.rb                    the ONLY composition root; picks the driver
                              from GREETER_CHANNEL (cli|http)
    hooks.rb                  capability gating + tag-validation + trace writing
lib/greeter_acceptance/
  ports/greeter_driver.rb     the ONLY interface steps may call
  drivers/cli_driver.rb       spawns `greeter <name>`; no counting/idempotency
  drivers/http_driver.rb      POST /greetings; capabilities: counting, idempotency
  capabilities.rb             the known capability set (single source of truth)
  trace.rb                    writes greeterhq.traceability.v1 per run
  ledger.rb                   merges per-channel traces into the ledger
spec/drivers/                 the driver-contract every adapter must pass
bin/merge-ledger              derives tmp/ledger.json from the per-channel traces
```

- Step definitions never mention exit codes, HTTP statuses, headers, or JSON —
  those idioms live inside the drivers.
- Scenarios needing a capability are tagged `@capability-<name>`; a driver
  without it records `not_applicable`. Every scenario also carries
  `@requirement-<slug>` and `@scenario-<slug>`, which become the trace's rows.
- Every driver passes `spec/drivers/greeter_driver_contract.rb`, which keeps all
  adapters substitutable behind the one port.

## Requirements

- Ruby 3.3.13
- Bundler
- A channel to drive:
  - **cli** — the `greeter` CLI on `PATH` (or pointed at by `GREETER_CLI_CMD`).
    Grab a release from
    [greeter-cli](https://github.com/greeterhq/greeter-cli/releases).
  - **http** — a reachable `greeter-http` endpoint (`GREETER_BASE_URL`). The
    driver sends `X-Greeter-Synthetic: true` by default, so it is safe against a
    deployed stage.

## Setup

```bash
bundle install
```

## Running the suite

The suite drives one channel per run; `GREETER_CHANNEL` selects the driver.

```bash
# CLI channel
GREETER_CHANNEL=cli GREETER_CLI_CMD=/path/to/greeter bundle exec cucumber

# HTTP channel
GREETER_CHANNEL=http \
  GREETER_BASE_URL="https://xxxxxxxxxx.execute-api.<region>.amazonaws.com" \
  bundle exec cucumber
```

Each run writes `tmp/traceability.json` plus a channel-tagged copy
(`tmp/traceability-<channel>.json`). Run both channels, then merge:

```bash
bin/merge-ledger tmp/traceability-cli.json tmp/traceability-http.json
# writes tmp/ledger.json
```

Other tests and lint:

```bash
bundle exec rspec spec/drivers   # the driver contract, per adapter
bundle exec rubocop              # lint
```

### Configuration

The composition root (`features/support/env.rb`) reads:

| Variable | Meaning | Default |
| --- | --- | --- |
| `GREETER_CHANNEL` | which channel to drive (`cli` or `http`) | (required) |
| `GREETER_CLI_CMD` | the greeter CLI command (cli channel) | `greeter` |
| `GREETER_CLI_DIR` | working directory for the CLI (cli channel) | (none) |
| `GREETER_BASE_URL` | the greeter-http base URL (http channel) | (required for http) |
| `ACCEPTANCE_REF` | recorded in the trace's `run.acceptance_ref` | `null` |

An unset or unknown `GREETER_CHANNEL` fails fast with a clear message.

## Adding a channel

A new channel (web, mobile, event, …) joins the suite without touching a single
feature file:

1. Add a driver under `lib/greeter_acceptance/drivers/` that includes
   `GreeterAcceptance::Ports::GreeterDriver` and declares its `capabilities`.
2. Wire it into `features/support/env.rb` behind a new `GREETER_CHANNEL` value.
3. Make it pass `spec/drivers/greeter_driver_contract.rb`.

The existing features run against it immediately; capability-gated scenarios it
cannot honour record `not_applicable` in its trace, never a failure.

## Versioning

Consumers pin this repo by git tag (`ACCEPTANCE_REF`), and tags follow semver:

- a new or stricter scenario that existing channels may fail is a **minor** bump
  at least;
- a removed scenario or a changed port method is **major**.

This repo never proposes changes to `greeter-core`, `greeter-cli`, or
`greeter-http`. If a channel misbehaves, the suite reports the gap and stops.

See `openspec/` for the specification of channel-neutral behaviour and the
driver contract.
