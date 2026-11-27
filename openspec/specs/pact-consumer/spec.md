# pact-consumer Specification

## Purpose

Defines the consumer contract between the suite's HTTP driver (consumer
`greeter-acceptance`) and the greeter HTTP service (provider `greeter-http`):
the interactions it records, how its specs run, and how CI publishes the pact
and records the suite's deployments in the Pact Broker.

## Requirements

### Requirement: The HTTP driver is the Pact consumer of greeter-http
The pact specs SHALL drive the real HTTP driver, obtained from the composition
root, against the Pact mock server, and SHALL write one pact between consumer
`greeter-acceptance` and provider `greeter-http` to `./pacts`. A pact run SHALL
start from no earlier pact file, so no stale interaction is published.

#### Scenario: A pact run writes the greeter-acceptance to greeter-http pact
- **WHEN** `bundle exec rspec -t pact spec/pact/providers` runs
- **THEN** every interaction is matched by a request the driver sent, and `pacts/greeter-acceptance-greeter-http.json` names consumer `greeter-acceptance` and provider `greeter-http` and holds only this run's interactions
- Maps to: `spec/pact/providers/greeter_http_spec.rb`

### Requirement: Pact specs are excluded from the default run
Examples tagged `:pact` SHALL NOT run in a plain `bundle exec rspec`, and SHALL
run when the `pact` tag is selected.

#### Scenario: The default run skips the pact specs
- **WHEN** `.github/workflows/ci.yml` and the RSpec configuration are read
- **THEN** the RSpec configuration excludes `:pact` by default, and the `rspec` job's command neither selects the `pact` tag nor names `spec/pact`
- Maps to: `spec/ci_workflow_spec.rb`

### Requirement: The contract records a new greeting
In provider state `no greetings for ada`, the pact SHALL expect a POST to
`/greetings` with body `{"name":"ada"}`, `Content-Type: application/json`,
`X-Greeter-Synthetic: true` and an `Idempotency-Key` matched as a UUID, to be
answered 201 with the success body and both version headers.

#### Scenario: A new greeting is answered 201
- **WHEN** the driver greets `ada` against the mock server in state `no greetings for ada`
- **THEN** the interaction matches, the response has status 201, the driver reports the neutral greeted outcome, and the pact records `guest_name` and `greeting` as strings, `count` as an integer, `greeted_at` as an ISO-8601 string, and `X-Greeter-Version` and `X-Greeter-Core-Version` matching `^\d+\.\d+\.\d+$`
- Maps to: `spec/pact/providers/greeter_http_spec.rb`

### Requirement: The contract records an idempotent replay
In provider state `ada has been greeted with key
0b0e3a52-6f1c-4b8e-9d2a-2f3c1e4d5a6b`, the pact SHALL expect the same request
carrying exactly that `Idempotency-Key`, answered 200 with the same body shape
and headers as a new greeting.

#### Scenario: A replay with a known key is answered 200
- **WHEN** the driver greets `ada` with idempotency key `0b0e3a52-6f1c-4b8e-9d2a-2f3c1e4d5a6b` in that state
- **THEN** the interaction matches, the response has status 200, the driver reports the neutral greeted outcome, and the pact records the same body and header matchers as the new greeting
- Maps to: `spec/pact/providers/greeter_http_spec.rb`

### Requirement: The contract records an invalid name
In provider state `any state`, the pact SHALL expect a POST to `/greetings` with
body `{"name":""}`, the synthetic header and a UUID-matched `Idempotency-Key`,
answered 422 with `error` exactly `invalid_name` and `message` matched as a
string.

#### Scenario: An empty name is answered 422 invalid_name
- **WHEN** the driver greets an empty name against the mock server in state `any state`
- **THEN** the interaction matches, the response has status 422, the driver's last neutral error is the invalid-name symbol, and the pact records `error` as `invalid_name` and `message` as any string
- Maps to: `spec/pact/providers/greeter_http_spec.rb`

### Requirement: The contract holds only requests the consumer makes
The pact SHALL hold exactly the new-greeting, replay and invalid-name
interactions. Every interaction SHALL carry `X-Greeter-Synthetic: true` and an
`Idempotency-Key`, because the driver always sends both.

#### Scenario: Three interactions, each with the synthetic header and a key
- **WHEN** the pact file written by the pact run is read
- **THEN** it has exactly three interactions, and every request carries `X-Greeter-Synthetic: true` and an `Idempotency-Key`
- Maps to: `spec/pact/providers/greeter_http_spec.rb`

### Requirement: Provider-chosen values are matched by type or pattern
The pact SHALL match `count` with an integer matcher, `greeted_at` with an
ISO-8601 pattern, the version headers with `^\d+\.\d+\.\d+$`, and the other
provider-chosen strings by type, so provider verification fails when one of
these fields is renamed, removed or retyped, and passes on any other value.

#### Scenario: Count is expected as an integer
- **WHEN** the pact file written by the pact run is read
- **THEN** each success response body has a `count` key and an integer matching rule on `$.count`, and no matching rule or body value pins an exact `count`, `greeted_at` or version
- Maps to: `spec/pact/providers/greeter_http_spec.rb`

### Requirement: CI runs the pact specs on every run
`ci.yml` SHALL run the pact specs in a `pact` job on every trigger, pull
requests included, with read-only permissions and no secret, and SHALL write
and upload the partial trace `repo-trace-pact`.

#### Scenario: The pact job runs the specs and uploads a partial trace
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `pact` has `needs: lint`, `permissions: {contents: read}`, no `if:`, no `secrets.` reference, runs `bundle exec rspec -t pact spec/pact/providers` with `--format RepoTraceFormatter` and `REPO_TRACE_PATH=tmp/repo-trace-pact.json`, and uploads `repo-trace-pact` with `retention-days: 1` and `if-no-files-found: error`
- Maps to: `spec/ci_workflow_spec.rb`

### Requirement: CI publishes the pact only from main and suite tags
A `pact-publish` job SHALL need `pact` and SHALL run only on push to `main` or
push of a `v*` tag. On `main` it SHALL publish `./pacts` with
`--consumer-app-version $GITHUB_SHA --branch main`. A pull request SHALL NOT
publish.

#### Scenario: Main publishes with the main branch
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `pact-publish` has `needs: pact`, runs only when the event is `push` and the ref is `refs/heads/main` or starts with `refs/tags/v`, and on `main` runs `pact-broker publish` from `pactfoundation/pact-cli` on the pact files with `--consumer-app-version` `$GITHUB_SHA` and `--branch main`
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: A pull request publishes no pact
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** the `pact-publish` condition is false for `pull_request` and `schedule` events, and no other job runs `pact-broker`
- Maps to: `spec/ci_workflow_spec.rb`

### Requirement: A suite tag on main publishes and records deployments
On push of a `v*` tag, `pact-publish` SHALL fail before publishing unless the
tagged commit is an ancestor of `origin/main`. It SHALL then publish without
`--branch` or `--tag`, and record a deployment of `greeter-acceptance` at
`$GITHUB_SHA` to `stage` and to `prod`.

#### Scenario: A tag publishes, then records stage and prod
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** on a tag ref, a step running `git merge-base --is-ancestor "$GITHUB_SHA" origin/main` comes before the publish step, the tag publish has neither `--branch` nor `--tag`, and after it `pact-broker record-deployment --pacticipant greeter-acceptance --version $GITHUB_SHA` runs with `--environment stage` and with `--environment prod`
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: A tag off main fails before publishing
- **WHEN** the ancestry check runs for a tagged commit that is not on `origin/main`
- **THEN** the step exits non-zero, so the publish and record-deployment steps do not run
- Maps to: `spec/ci_workflow_spec.rb`

### Requirement: The broker token reaches only the publish steps
`PACT_BROKER_TOKEN` SHALL be an environment secret of the `pact-broker` GitHub
Environment, used only by the `pact-publish` job. A step SHALL receive it only
through its own `env:`, and only if the step runs `pact-broker`. Docker SHALL
receive it by name with `-e PACT_BROKER_TOKEN`. No job-level or workflow-level
`env:` and no other step SHALL reference it, and no `run:` text SHALL contain
the expression `secrets.PACT_BROKER_TOKEN`.

#### Scenario: The token is scoped to the pact-broker steps
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** every step whose `env` references `secrets.PACT_BROKER_TOKEN` runs `pact-broker`, every step that runs `pact-broker` gets `PACT_BROKER_BASE_URL` from `vars` and `PACT_BROKER_TOKEN` from `secrets` in its own `env`, no workflow or job `env` holds either, no `run:` of `pact-publish` contains `${{`, and `pact-publish` has `permissions: {contents: read}` and a checkout with `persist-credentials: false`
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: The publish job runs in the pact-broker environment
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `pact-publish` has `environment: pact-broker`, no other job names that environment, and the workflow has no `pull_request_target` trigger
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: The token reaches the container by name only
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** every `docker run` in `pact-publish` has `--rm`, passes `PACT_BROKER_BASE_URL` and `PACT_BROKER_TOKEN` as `-e NAME` with no `=`, and mounts `"$PWD/pacts:/pacts:ro"`, and no `pact-broker` command has `--verbose` or `-v`
- Maps to: `spec/ci_workflow_spec.rb`

### Requirement: The publish job checks its inputs before using the token
Before any step that has the broker token, `pact-publish` SHALL fail unless:
- the downloaded pact directory holds only the `greeter-acceptance` to `greeter-http` pact;
- the broker URL uses HTTPS;
- on a tag, the tag name equals `v` followed by the suite version.

These checks SHALL use standard-library Ruby only and read their inputs from `env`.

#### Scenario: Only the greeter-acceptance to greeter-http pact is published
- **WHEN** the pact check step runs against a pact directory holding an extra file, a pact whose consumer is not `greeter-acceptance`, or a pact whose provider is not `greeter-http`
- **THEN** it exits non-zero naming the problem, and it exits 0 for a directory holding only `greeter-acceptance-greeter-http.json` with those names; in `ci.yml` the step comes after the download and before every step that has the token
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: A non-HTTPS broker URL stops the job
- **WHEN** the check step runs with a `PACT_BROKER_BASE_URL` that does not start with `https://`
- **THEN** it exits non-zero naming `PACT_BROKER_BASE_URL`, and it exits 0 for an `https://` URL
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: A tag that does not match the suite version stops the job
- **WHEN** the tag check step runs with a `GITHUB_REF_NAME` other than `v` followed by `GreeterAcceptance::VERSION`
- **THEN** it exits non-zero naming both values, and it exits 0 when they match; in `ci.yml` the step runs on tags only, before the publish step, and has no token
- Maps to: `spec/ci_workflow_spec.rb`
