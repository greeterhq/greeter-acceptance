## Why

greeter-docs needs to show, per repo, which requirements exist and whether the
tests that verify them passed. In greeter-acceptance nothing machine-readable
links a requirement to a test, and nothing fails when the two drift apart. The
five `greeting` requirements are verified by Cucumber scenarios tagged
`@requirement-greeting-*`, which do not match the spec headings. The tooling
capabilities are verified by RSpec examples that carry no requirement metadata.

This change follows `../greeter-core/openspec/changes/adopt-live-docs`, with the
differences listed below.

## What Changes

- Define the shared slug rule (heading lowercased, each run of characters other
  than a-z and 0-9 replaced by one `-`, `-` trimmed from both ends) as a helper
  in `spec/support/`.
- Add `openspec/requirement-tags.yml`, mapping each `greeting` heading slug to
  its existing Cucumber tag. The existing `@requirement-greeting-*` tags are not
  renamed, because they are the ledger's requirement keys.
- Tag RSpec examples that verify tooling requirements (`driver-contract`,
  `traceability`, `ledger-publication`, `acceptance-gate`, `environment-targets`,
  and the new `live-docs-traceability`) with `requirement: '<slug>', scenario: '<slug>'`.
  Together with `greeting` (through the tag map) this covers all six capabilities.
  This edits existing files under `spec/` and is the one sanctioned exception to
  "never edit spec/": it may only add `requirement:`/`scenario:` metadata and
  tagged wrapper contexts around unchanged lines. A task verifies this mechanically.
- Add `spec/support/repo_trace_formatter.rb` (RSpec formatter writing a
  `greeterhq.repo-trace.v1` file, `repo` `greeter-acceptance`), `spec/support/repo_trace/`
  helpers, and `bin/merge-repo-trace`, copied from greeter-cli and extended to merge
  any number of inputs.
- Add `spec/trace_check_spec.rb`. It fails when a requirement heading has no
  verifying test, when a tag names no heading, or when an RSpec scenario slug is
  not a scenario of its requirement. For `greeting` it applies
  `openspec/requirement-tags.yml` to the tags in `features/**/*.feature`.
- `ci.yml` is restructured, because the driver contract (`spec/drivers/`) needs real
  channels:
  - `rspec`: everything except `spec/drivers/**/*_spec.rb`, writing the partial trace
    `tmp/repo-trace-spec.json`.
  - `drivers`: a matrix over `cli` and `http`, each leg running its driver spec against
    the real channel and writing `tmp/repo-trace-drivers-<channel>.json`. `http` targets the
    stage `base_url` from `config/environments.yml`; `cli` installs the latest
    greeter-cli release.
  - `trace`: merges the three partial traces. On `main` and on the weekly schedule
    (`17 6 * * 1`), when every input job succeeded, it uploads `repo-trace`.
  - `notify-docs` (needs `trace`): sends `repository_dispatch` `docs-refresh` with
    `client_payload[repo]=greeter-acceptance`.
  - Concurrency becomes `ci-${{ github.event_name }}-${{ github.ref }}`, cancelling only
    pull-request runs, so a run on `main` and a weekly run do not cancel each other.
- `record.yml`: add a `notify-docs` job after `publish`, a matrix over the run's
  environments (new `environments` output on `resolve`), sending `docs-refresh` with
  `client_payload[repo]=greeter-acceptance` and `client_payload[ledger]=<environment>`,
  using its own `greeterhq-dispatch` token, never the ledger-writer token.

## Capabilities

### New Capabilities
- `live-docs-traceability` (tooling capability, verified by RSpec): requirement-to-test
  tagging and the tag map, the trace-check, the repo-trace file and its merge, and the
  two `docs-refresh` publications (CI and record mode).

### Modified Capabilities
<!-- None. Existing requirement text is unchanged; examples only gain tags. -->

## Differences from greeter-core

- `greeting` is a channel-behaviour capability verified by Cucumber. Its requirements
  are matched through `openspec/requirement-tags.yml`, not RSpec tags. Its `@scenario-*`
  tags and scenario names do not match the spec scenario headings and are not renamed,
  so the trace-check does not compare scenario slugs for `greeting`.
- `tmp/traceability.json` (`greeterhq.traceability.v2`, the per-channel run file) is
  not changed; the repo trace is a separate file. `greeting` results reach greeter-docs
  through the ledger (`client_payload[ledger]`), not through the repo trace.
- The repo trace covers `rspec` results only. Cucumber runs only in record mode against a
  deployed channel, and the suite code that mode runs does not change.
- Driver specs need a real channel, so CI runs them in a separate matrix job and merges
  three partial traces. Pushes, pull requests and the weekly run all call the stage
  http target and the latest cli release.
- Two dispatches: one from `ci.yml`, one per ledger environment from `record.yml`.

## Prior change

`harden-candidate-install` will be applied, released as v0.3.0 and archived before this
change is applied; this branch is then rebased on `main`. Its `acceptance-gate` and
`ledger-publication` requirements are then ordinary main-spec requirements, tagged here.

## Non-goals

- Any change to `lib/`, `features/` step definitions, `features/support/`, the Cucumber
  tags, or existing requirement text. No new suite tag, because record mode runs the
  same suite code.
- Any change to `tmp/traceability.json` or its schema.
- Rendering the docs site (owned by greeter-docs).
- A fallback when dispatch credentials are missing: a failing `notify-docs` is intended.
- Dependency scanning and pinning actions to commit SHAs.

## Consumers affected

- greeter-docs: reads artifact `repo-trace` and receives `docs-refresh` with
  `client_payload[repo]` (and, from record mode, `client_payload[ledger]`). It must
  accept schema `greeterhq.repo-trace.v1` and treat both payload fields as untrusted.
- greeter-core, greeter-cli, greeter-http: none.

## Impact

- `openspec/requirement-tags.yml` (new); `spec/` (tags on existing examples; new
  `spec/support/`, `spec/fixtures/`, `spec/bin/`, new specs); `bin/merge-repo-trace`;
  `.rubocop.yml` exclusions.
- `.github/workflows/ci.yml` and `.github/workflows/record.yml`.
- Load on the stage environment: every CI run (push, pull request, weekly) calls the stage
  http target. Accepted.
- Repo configuration, to be added by the maintainer before merge:
  `vars.DISPATCH_APP_CLIENT_ID`, `secrets.DISPATCH_APP_PRIVATE_KEY`, and the
  `greeterhq-dispatch` app installed on `greeterhq/greeter-docs`.
- `.talismanrc` checksums for edited tracked files.
