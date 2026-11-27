# Proposal

## Why

The suite checks greeter-http's behaviour only after it is deployed to stage.
Nothing tells greeter-http, before it ships, that a change to its response
(a renamed or retyped `count`, a missing version header) breaks the one client
that reads it: this suite's HttpDriver. Making HttpDriver a Pact consumer
publishes exactly what it relies on to the Pact Broker, so greeter-http can
verify against it and `can-i-deploy` can block a breaking release.

## What Changes

- HttpDriver becomes the Pact consumer `greeter-acceptance` of provider
  `greeter-http`, using pact-ruby v2 (`gem 'pact', '~> 2.1'`, already in the
  Gemfile and lockfile as 2.1.2).
- New consumer spec `spec/pact/providers/greeter_http_spec.rb`, tagged `:pact`
  and excluded from the default `rspec` run. It runs with
  `bundle exec rspec -t pact spec/pact/providers` and drives the real HttpDriver
  against the Pact mock server. It defines three interactions, each with a
  provider state:
  - `no greetings for ada`: a new greeting answers 201.
  - `ada has been greeted with key 0b0e3a52-6f1c-4b8e-9d2a-2f3c1e4d5a6b`: a
    replay with that key answers 200.
  - `any state`: an empty name answers 422 `invalid_name`.
- Values the provider decides (`guest_name`, `greeting`, `count`,
  `greeted_at`, the error `message`, both version headers, a generated
  `Idempotency-Key`) are matched by type or pattern, never by exact value.
- `ci.yml` gets a `pact` job that runs the pact specs on every run (pull
  requests included) and uploads a fourth partial trace, `repo-trace-pact`.
  The `trace` job needs it and merges it with the other three.
- `ci.yml` gets a `pact-publish` job. It runs only on push to `main` and on push
  of a `v*` tag, and is the only place the broker token appears.
  - On `main` it publishes `./pacts` with `--consumer-app-version $GITHUB_SHA --branch main`.
  - On a `v*` tag it first fails unless the tagged commit is an ancestor of
    `origin/main`. It then publishes without `--branch` and without `--tag`, and
    records a deployment of `greeter-acceptance` at `$GITHUB_SHA` to `stage`
    and to `prod`.
- `GreeterAcceptance::VERSION` goes to `0.4.0`.

## Non-goals

- No missing-`Idempotency-Key` (400) interaction. HttpDriver always sends a key,
  and a consumer contract describes only requests the consumer makes.
- No change to the GreeterDriver port, to any driver's behaviour, or to any
  Cucumber feature or step definition.
- No provider verification and no provider-state setup. Both belong to
  greeter-http and are not proposed from here.
- No Pact publication or deployment recording from `gate.yml` or `record.yml`.
- No `can-i-deploy` check in this repo's pipelines.

## Channels affected

- **http**: HttpDriver is exercised against the Pact mock server. Its code does
  not change.
- **cli**: none.

## Semver impact

Minor: the suite tag becomes `v0.4.0`. No scenario is added, removed or made
stricter, and the port does not change, so existing channels pass `v0.4.0` as
they passed `v0.3.0`. No consumer repo has to bump `ACCEPTANCE_REF`. greeter-cli
and greeter-http may move to `v0.4.0` whenever they like.

## Capabilities

### New Capabilities
- `pact-consumer`: covers what the consumer contract with greeter-http contains,
  how its specs are run, and how CI publishes the pact and records deployments.
  This is a tooling capability, verified by RSpec examples.

### Modified Capabilities
- `live-docs-traceability`: the `trace` job also needs the `pact` job, downloads
  and merges the `repo-trace-pact` partial, and treats a failed `pact` job like
  a failed `rspec` or `drivers` job.

## Impact

- New: `spec/pact/providers/greeter_http_spec.rb`, `/pacts/` in `.gitignore`.
- Changed: `spec/spec_helper.rb` (excludes `:pact` by default),
  `.github/workflows/ci.yml` (new `pact` and `pact-publish` jobs, `trace` needs
  `pact`), `spec/ci_workflow_spec.rb`, `lib/greeter_acceptance/version.rb`,
  `README.md`.
- External: the Pact Broker at `vars.PACT_BROKER_BASE_URL`, authenticated with
  `secrets.PACT_BROKER_TOKEN`. Both are already set on this repo.
- **Gap in greeter-http, outside this repo:** greeter-http has no provider
  verification for the three provider states above yet. Its `cd.yml` has no
  `can-i-deploy`, so recording `greeter-acceptance` as deployed to stage and
  prod blocks nothing today. greeter-http's verification is expected to arrive
  with pending pacts enabled, before its first `can-i-deploy`. This proposal
  describes the gap and goes no further.
