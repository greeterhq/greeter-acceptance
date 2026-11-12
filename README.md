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
`greeterhq.traceability.v2`), recording what was tested and whether the channel's
own reported version could be verified; merging the per-channel files produces
a ledger, the requirement-by-channel matrix that is the suite's headline
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
    env.rb                    the Cucumber World: exposes the driver, built by
                              the composition root
    hooks.rb                  capability gating + tag-validation + trace writing
lib/greeter_acceptance/
  composition_root.rb         the ONLY place a driver is constructed; picks it
                              from GREETER_CHANNEL (cli|http). env.rb and bin/*
                              only call it
  ports/greeter_driver.rb     the ONLY interface steps may call
  drivers/cli_driver.rb       spawns `greeter <name>`; no counting/idempotency
  drivers/http_driver.rb      POST /greetings; capabilities: counting, idempotency
  capabilities.rb             the known capability set (single source of truth)
  observed.rb                 decorator that remembers infrastructure errors and
                              build information across a scenario
  run_record.rb               the run's rows and context; writes
                              greeterhq.traceability.v2
  version.rb                  the suite version (matches the git tag)
  deployed.rb                 the deployed record (greeterhq.deployed.v1)
  ledger.rb                   derives the ledger (greeterhq.ledger.v2)
  ledger_renderer.rb          renders the ledger as LEDGER.md
spec/drivers/                 the driver-contract every adapter must pass
bin/merge-ledger              builds ledger.json and LEDGER.md from channel results
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

Each run writes `tmp/traceability.json`. Keep each run's file under its channel's
name, run both channels, then merge:

```bash
mkdir -p tmp/channels
cp tmp/traceability.json tmp/channels/cli.json    # after the cli run
cp tmp/traceability.json tmp/channels/http.json   # after the http run
bin/merge-ledger --channels tmp/channels
# writes tmp/ledger/ledger.json and tmp/ledger/LEDGER.md
```

Other tests and lint:

```bash
bundle exec rspec spec/drivers   # the driver contract, per adapter
bundle exec rubocop              # lint
```

### Configuration

The composition root (`lib/greeter_acceptance/composition_root.rb`) reads:

| Variable | Meaning | Default |
| --- | --- | --- |
| `GREETER_CHANNEL` | which channel to drive (`cli` or `http`) | (required) |
| `GREETER_CLI_CMD` | the greeter CLI command (cli channel) | `greeter` |
| `GREETER_CLI_DIR` | working directory for the CLI (cli channel) | (none) |
| `GREETER_BASE_URL` | the greeter-http base URL (http channel) | (required for http) |
| `GREETER_ENVIRONMENT` | recorded as the trace's `run.environment` | `local` |
| `GREETER_EXPECTED_VERSION` | the channel version the run is verified against | (none) |
| `GREETER_EXPECTED_SHA` | recorded as the trace's `run.channel_sha` | (none) |
| `GITHUB_RUN_ID` or `GREETER_RUN_ID` | recorded as the trace's `run.run_id` | (none) |
| `GREETER_RELEASED_AT` | recorded as the trace's `run.released_at` | (none) |

An unset or unknown `GREETER_CHANNEL` fails fast with a clear message.

## Gate and record

Two workflows use the suite in CI. Both run a released suite version (a git tag),
never the default branch. Record mode needs a tag that contains its code, so
v0.2.0 or later.

### Gate: before a release

A channel repo calls `gate.yml` to prove a candidate passes before it publishes
or promotes it. The gate is read-only and writes nothing to a ledger.

```yaml
jobs:
  build:
    # builds the tarball and uploads it as an artifact
  gate:
    needs: build
    uses: greeterhq/greeter-acceptance/.github/workflows/gate.yml@v1
    with:
      acceptance_ref: v0.2.0   # the suite version this repo pins
      channel: cli
      candidate_version: v0.1.3
      candidate_sha: ${{ github.sha }}
      artifact_name: dist
      artifact_file: greeter-cli-v0.1.3.tar.gz
  release:
    needs: gate                # does not run if the gate fails
```

| Input | Meaning |
| --- | --- |
| `acceptance_ref` | the released suite version to run (required) |
| `channel` | `cli` or `http` (required) |
| `candidate_version` | the candidate's version, e.g. `v1.2.3` (required) |
| `candidate_sha` | the candidate's commit (required) |
| `environment` | service channel: the environment the candidate is deployed to (default `stage`) |
| `artifact_name`, `artifact_file` | artifact channel: the uploaded artifact and the tarball inside it |
| `allow_unverified` | accept a channel that reports no version; the result is marked unverified |

A service channel is tested where it is deployed. The target comes from
`config/environments.yml`, never from an input.

### Record: after a release

`record.yml` runs the suite against what is deployed and records the result on a
ledger branch: `ledger-prod` or `ledger-stage`, one per environment. Each branch
holds `deployed.json`, `ledger.json`, `LEDGER.md` and one file per channel.
Generated data only: CI ignores these branches.

A channel announces a release with a `repository_dispatch` event of type
`channel-released`:

```yaml
- name: Announce the release
  run: >
    gh api repos/greeterhq/greeter-acceptance/dispatches
    -f event_type=channel-released
    -F 'client_payload[channel]=http'
    -F 'client_payload[version]=v1.2.3'
    -F 'client_payload[sha]=def4567'
    -F 'client_payload[environment]=prod'
```

The payload carries `channel`, `version`, `sha` and `environment`, and for an
artifact channel an `artifact` tag. It is validated before use, and the target is
looked up in `config/environments.yml`.

Other triggers:

- Pushing a suite tag `v*` re-tests everything currently in `deployed.json`.
- A manual run (Actions, Record, Run workflow) tests one channel from the inputs.
  `rerun_all` re-tests every channel in every environment instead.
- `force` lets a manual run record a version older than the one recorded, for a
  rollback. The ledger records who forced it.

Without `force`, an older version than the recorded one is refused.

## Adding a channel

A new channel (web, mobile, event, …) joins the suite without touching a single
feature file:

1. Add a driver under `lib/greeter_acceptance/drivers/` that includes
   `GreeterAcceptance::Ports::GreeterDriver`, declares its `capabilities`, and
   implements `build_info` (see below).
2. Wire it into `lib/greeter_acceptance/composition_root.rb` behind a new
   `GREETER_CHANNEL` value, and add the channel to `CompositionRoot.channels`.
3. Make it pass `spec/drivers/greeter_driver_contract.rb`.

The existing features run against it immediately; capability-gated scenarios it
cannot honour record `not_applicable` in its trace, never a failure.

### What a driver reports

- **Build information.** `build_info` returns a `BuildInfo` with the channel
  version and the core version the channel reports about itself, or `nil` when
  the channel does not report them. Asking for it must not change the channel's
  state (no greeting, no count). A run is attributed to the version the driver
  observed, so a channel that reports nothing is recorded as `unobserved`.
- **Infrastructure errors.** A driver never raises because of its channel. When
  the channel cannot be reached, or returns something the driver does not
  recognise, `greet` returns the `:infrastructure_error` outcome and sets
  `last_error` to `:infrastructure_error`. The scenario that hit it is recorded
  as `error`, not `failed`.

## Versioning

Consumers pin this repo by git tag (`ACCEPTANCE_REF`), and tags follow semver:

- a new or stricter scenario that existing channels may fail is a **minor** bump
  at least;
- a removed scenario or a changed port method is **major**.

This repo never proposes changes to `greeter-core`, `greeter-cli`, or
`greeter-http`. If a channel misbehaves, the suite reports the gap and stops.

See `openspec/` for the specification of channel-neutral behaviour and the
driver contract.
