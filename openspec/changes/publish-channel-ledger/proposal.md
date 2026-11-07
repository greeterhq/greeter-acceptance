# Proposal

## Why

The v0.1.0 suite runs one channel at a time and writes a throwaway ledger. It
cannot stop a bad release, it cannot say which version of which channel a result
belongs to, and it keeps nothing between runs. Channels release independently,
so a durable record has to be built one channel at a time: when one channel
releases, only that channel is re-tested and its result is merged with what is
already on file for the others.

## What Changes

- Add a **gate** mode: a read-only reusable workflow that a channel's release
  pipeline calls. It runs the suite at the caller's pinned `ACCEPTANCE_REF`
  against the candidate (the built artifact for an artifact channel, the stage
  environment for a service channel) and fails the caller's release on a failed
  or errored result.
- Add a **record** mode: after a channel reaches an environment (a
  `channel-released` repository dispatch, a new suite tag, or a manual run), run
  the latest published suite against what is deployed and publish the result to a
  per-environment ledger branch (`ledger-prod`, `ledger-stage`).
- Publish each ledger branch as `channels/<channel>.json` (latest result per
  channel), `deployed.json` (`greeterhq.deployed.v1`, what is deployed), and the
  generated `ledger.json` (`greeterhq.ledger.v2`) and `LEDGER.md`.
- Add `build_info` to the `GreeterDriver` port so a run is attributed to the
  channel version it actually tested (channel version and core version), and
  record the run as verified, mismatched, inconsistent or unobserved.
- Extend the neutral outcome vocabulary with `infrastructure_error`. Drivers
  return it instead of raising, and scenarios hit by it are recorded with status
  `error`, which replaces a previous `passed` the way `failed` does.
- Distinguish ledger **cell** statuses (`passed`, `failed`, `error`,
  `not_applicable`, `missing`) and ledger **column** states (`current`, `stale`,
  `missing`), so a result is never shown as current when it was produced by an
  older suite or for a version that is no longer deployed.
- Resolve every service target from a committed `config/environments.yml` read
  from the default branch, with a host-pattern check. A target URL is never taken
  from an event, an input, or a caller.
- Make publishing safe and convergent: the publishing stage runs only stdlib
  Ruby from the suite tag and treats the channel's result as untrusted data;
  retries re-read the branch and regenerate instead of rebasing; an older channel
  version does not overwrite a newer result unless `FORCE=true`.
- Move the composition root from `features/support/env.rb` to
  `lib/greeter_acceptance/composition_root.rb` so `bin/` scripts can build a
  driver. This supersedes the rule from `add-neutral-acceptance-suite` that
  `env.rb` is the only composition root. `openspec/config.yaml`, `README.md`, the
  `env.rb` comment and `.kiro/steering/architecture.md` are updated to match.

## Capabilities

### New Capabilities
- `acceptance-gate`: the read-only, reusable pre-release gate: pinned suite
  version, candidate under test, version verification, and pass/fail semantics.
- `ledger-publication`: record mode and publication: triggers, event validation,
  per-environment ledger branches, the deployed record, convergent publishing,
  version ordering, forced publication, and untrusted-data handling.
- `environment-targets`: how a run's target is resolved from committed
  configuration and checked, never taken from an event or caller input.

### Modified Capabilities
- `driver-contract`: the port surface gains build information; the neutral
  outcomes gain `infrastructure_error`; a new requirement defines build
  information reporting.
- `traceability`: trace rows gain the `error` status and a run context; the
  ledger becomes a requirement-by-channel matrix over all known channels, with
  `missing` cells and `current`/`stale`/`missing` columns; new requirements cover
  infrastructure errors, version attribution, and deterministic generation.

## Impact

**Channels affected:** `cli` and `http`. Both drivers implement `build_info` and
return `infrastructure_error` instead of raising. The gate and record modes work
per channel and take new channels without changing the workflows.

**Non-goals:**
- No change to greeter-core, greeter-cli or greeter-http (see Dependencies).
- No cross-channel regression comparison in the gate (for example comparing a
  candidate against `ledger-prod`); the gate judges the candidate on its own.
- No new channels (`WebDriver`, `MobileDriver`, `EventDriver`) and no Pact
  consumer wiring (Card 3).
- No new feature scenarios: the greeting behaviour is unchanged.
- No docs-site rendering; greeter-docs reads the ledger branches on its own.

**New and changed code:** `lib/greeter_acceptance/` (composition root, run
record, ledger v2, deployed record, renderer, environments, publisher, payload
validation), `bin/` (probe, resolve, publish, merge-ledger), `config/
environments.yml`, `.github/workflows/` (record, gate shim; `ci.yml` ignores the
ledger branches), and `docs/` (trace v2, ledger v2, deployed v1).

**Semver:** the last tag is `v0.1.0`; this is the next minor, `v0.2.0`, because
the suite is pre-1.0 and breaking changes ride a minor. Breaking for anyone who
reads the output: `tmp/traceability.json` moves to a v2 schema, the ledger moves
from `greeterhq.ledger.v1` to `v2`, a driver that used to raise on an
infrastructure failure now yields `error`, and the port gains a method. I could
not check whether any repo pins `v0.1.0`. No known consumer must bump
`ACCEPTANCE_REF`, but `greeter-cli` and `greeter-http` pin the new tag when they
adopt the gate, and anything parsing v1 trace or ledger files must be updated
first.

**Dependencies on the channels (described, not requested):**
- greeter-http does not yet report its version or core version. Verification
  needs them on every response, including error responses; until then HTTP
  results are recorded as `unobserved`.
- Both app repos need to send `channel-released` with a token that can dispatch
  to this repository, and call the gate from their release jobs.
- An http release flow needs to deploy to stage before the gate runs.
- greeter-docs needs a `docs-refresh` listener if it renders the ledger.
