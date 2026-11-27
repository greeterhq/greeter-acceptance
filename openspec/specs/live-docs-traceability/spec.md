# live-docs-traceability Specification

## Purpose

Defines how greeter-acceptance makes its requirements and test results
readable by greeter-docs: tagging tests to requirements (with the tag map for
greeting), the trace check, the repo-trace file and how its partial traces are
merged, and the docs-refresh dispatches sent from CI and from record runs.

## Requirements

### Requirement: Every requirement has a verifying test
Every known `### Requirement:` heading SHALL have a verifying test: for a tooling
capability, an RSpec example tagged `requirement: '<slug>'`; for `greeting`, a
Cucumber scenario carrying the tag that `openspec/requirement-tags.yml` maps to
the slug. A slug is the heading lowercased with each run of characters other than
a-z and 0-9 replaced by one `-` and the ends trimmed. A requirement with no
verifying test SHALL fail the suite, naming it and its spec file.

#### Scenario: Slug rule turns headings into slugs
- **WHEN** the slug function is given the headings in the slug table (for example `A channel greets a valid guest`, `Record mode uses the latest published suite version`, and this repo's real requirement and scenario headings)
- **THEN** it returns `a-channel-greets-a-valid-guest`, `record-mode-uses-the-latest-published-suite-version`, and the expected slug for every other row, with no camel-case splitting
- Maps to: `spec/slug_spec.rb`

#### Scenario: Tooling requirement with no tagged example fails and is named
- **WHEN** the trace-check runs against a fixture `spec.md` containing a tooling requirement that no example is tagged with
- **THEN** it fails with a message naming that requirement's slug and the fixture file
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: Greeting requirement with no mapped Cucumber tag fails and is named
- **WHEN** the trace-check runs against a fixture channel-behaviour requirement whose mapped tag is carried by no Cucumber scenario
- **THEN** it fails with a message naming the requirement slug, the mapped tag and the fixture file
- Maps to: `spec/trace_check_spec.rb`

### Requirement: Tagged tests must match a requirement
An RSpec example whose `requirement:` slug matches no known requirement, or whose
`scenario:` slug is not a scenario of its requirement, SHALL fail the suite,
naming the slug and file. Known headings come from `openspec/specs/**/spec.md`
and the ADDED and MODIFIED sections of non-archived changes. A Cucumber
`@requirement-*` tag that is not a value in `openspec/requirement-tags.yml` SHALL
also fail the suite.

#### Scenario: Unknown requirement slug fails and is named
- **WHEN** the trace-check runs with an example tagged with the requirement slug `no-such-requirement`
- **THEN** it fails with a message naming `no-such-requirement` and the example's file
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: Scenario slug is matched only within its requirement
- **WHEN** the trace-check runs with an example whose scenario slug exists only under a different requirement, and another whose scenario slug equals its own requirement's slug
- **THEN** it fails naming the first example's scenario, requirement and file, and reports no problem for the second
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: Requirements in in-flight changes are known
- **WHEN** the trace-check also reads change deltas and an example is tagged with a requirement or scenario found only in an ADDED or MODIFIED section of a change that is not archived, or found only in an archived change, or only in a REMOVED or RENAMED section
- **THEN** the first is known and reports no problem, and the others are reported as unknown with the example's file and line
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: A Cucumber requirement tag outside the map fails and is named
- **WHEN** a fixture feature carries `@requirement-greeting-unmapped` and the map has no such value
- **THEN** the trace-check fails naming `greeting-unmapped` and the feature file
- Maps to: `spec/trace_check_spec.rb`

### Requirement: The requirement-tag map covers the greeting headings
`openspec/requirement-tags.yml` SHALL map the slug of every `greeting`
requirement heading to the existing `@requirement-` tag suffix that verifies it,
and SHALL contain no key that is not a heading slug. The existing Cucumber tags
SHALL NOT be renamed.

#### Scenario: Every greeting heading maps to a tag that exists
- **WHEN** the trace-check reads the real `openspec/requirement-tags.yml`, `openspec/specs/greeting/spec.md` and `features/*.feature`
- **THEN** each of the five greeting heading slugs is a key, each value is carried by a Cucumber scenario, and there are no other keys
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: A key that is not a heading slug fails and is named
- **WHEN** the trace-check runs with a map key that matches no heading in the fixture spec
- **THEN** it fails naming that key and the map file
- Maps to: `spec/trace_check_spec.rb`

### Requirement: Repo trace contains only slugs, statuses, locations and run metadata
The formatter SHALL write a file in schema `greeterhq.repo-trace.v1` with one
result per example tagged with both `requirement` and `scenario`. It SHALL NOT
write example descriptions, failure messages, or any other field, because
descriptions can contain guest names. It SHALL NOT read or write
`tmp/traceability.json`.

#### Scenario: Formatter writes the v1 document
- **WHEN** a suite with one passing and one failing tagged example is run with the formatter
- **THEN** the file has `schema` `greeterhq.repo-trace.v1`, `repo` `greeter-acceptance`, `sha` (`GITHUB_SHA` or `git rev-parse HEAD`), `recorded_at` (UTC ISO 8601), `run_id` (`GITHUB_RUN_ID` or `null`), and two `results` with statuses `passed` and `failed`, `source` `rspec`, and `spec/...rb:LINE` locations
- Maps to: `spec/repo_trace_formatter_spec.rb`

#### Scenario: Formatter tells skipped from pending
- **WHEN** a suite with one example marked `skip` and one marked `pending`, both tagged, is run with the formatter
- **THEN** the skipped example has status `skipped` and the pending example has status `pending`
- Maps to: `spec/repo_trace_formatter_spec.rb`

#### Scenario: Formatter refuses malformed values
- **WHEN** a tagged example has a requirement or scenario value that is not a lowercase slug (for example `Alice Smith`), or the environment supplies a `GITHUB_SHA` that is not 40 hex characters or a `GITHUB_RUN_ID` that is not digits
- **THEN** the formatter raises an error naming the field and writes no file
- Maps to: `spec/repo_trace_formatter_spec.rb`

#### Scenario: Formatter omits descriptions
- **WHEN** a tagged example whose description contains `Alice Smith` is run with the formatter
- **THEN** the written file does not contain `Alice Smith` and each result has exactly the keys `requirement`, `scenario`, `status`, `source`, `location`
- Maps to: `spec/repo_trace_formatter_spec.rb`

#### Scenario: Formatter leaves the per-channel run file alone
- **WHEN** a tagged suite is run with the formatter while `tmp/traceability.json` exists
- **THEN** that file's bytes are unchanged and the formatter wrote only to the `REPO_TRACE_PATH` file
- Maps to: `spec/repo_trace_formatter_spec.rb`


### Requirement: Shared-example results are located at their inclusion
For an example that comes from shared examples, the formatter SHALL record the
location of the `it_behaves_like` (or `include_examples`) line that included it, so
that the same contract included by two driver specs gives distinct locations.

#### Scenario: Two inclusions of one shared example do not collide
- **WHEN** a fixture shared example is included by two fixture files, each inside a context tagged with the same requirement and scenario
- **THEN** the trace has one result per including file, each located at its own `it_behaves_like` line, and the two do not collapse
- Maps to: `spec/repo_trace_formatter_spec.rb`

### Requirement: Per-job traces merge into one trace
`bin/merge-repo-trace` SHALL merge any number of trace files into one
`greeterhq.repo-trace.v1` file containing every result. It SHALL fail, writing
nothing, when the inputs differ in `sha` or `run_id`, when an input is outside the v1
shape (including a `schema` other than `greeterhq.repo-trace.v1` or a `repo` other
than `greeter-acceptance`), or when the same result appears in two inputs.

#### Scenario: Merge combines all traces
- **WHEN** three valid trace files with the same schema, repo, sha and run_id and disjoint results are merged
- **THEN** the output has the same schema, repo, sha and `run_id`, the latest `recorded_at`, and all results sorted by location, requirement and scenario
- Maps to: `spec/bin/repo_trace_merge_spec.rb`

#### Scenario: Merge rejects mismatched inputs
- **WHEN** any two files differ in `sha` or `run_id` (including `null` against a value)
- **THEN** the merge exits non-zero with a message naming the differing field and writes no output file
- Maps to: `spec/bin/repo_trace_merge_spec.rb`

#### Scenario: Merge rejects inputs outside the v1 shape
- **WHEN** an input has a `schema` other than `greeterhq.repo-trace.v1`, a `repo` other than `greeter-acceptance`, an unknown top-level key, a result with an extra key, a `status` outside `passed|failed|pending|skipped`, a `source` other than `rspec`, or a value that does not match its pattern
- **THEN** the merge exits non-zero naming the file and field and writes no output file
- Maps to: `spec/bin/repo_trace_merge_spec.rb`

#### Scenario: Merge rejects a duplicated result
- **WHEN** the same requirement, scenario and location appear in two files
- **THEN** the merge exits non-zero naming that requirement and location and writes no output file
- Maps to: `spec/bin/repo_trace_merge_spec.rb`

### Requirement: CI runs the driver contract against real channels
`ci.yml` SHALL run RSpec without `spec/drivers/**/*_spec.rb` in an `rspec` job, and
run each driver spec in a `drivers` matrix job over `cli` and `http` against the
real channel. Each job SHALL write its own partial trace.

#### Scenario: The rspec job excludes the driver specs
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `rspec` has `needs: lint`, `permissions: {contents: read}`, runs `bundle exec rspec --exclude-pattern 'spec/drivers/**/*_spec.rb'` with `--format RepoTraceFormatter` and `REPO_TRACE_PATH=tmp/repo-trace-spec.json`, and uploads `repo-trace-spec` with `retention-days: 1` and `if-no-files-found: error`
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: The http leg targets stage from committed configuration
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `drivers` has `needs: lint`, `permissions: {contents: read}`, `strategy.fail-fast: false` and a `channel` matrix of `cli` and `http`, and the `http` leg sets `GREETER_BASE_URL` from the `stage` `http` `base_url` in `config/environments.yml` read at run time, with no URL literal in the workflow
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: The cli leg installs the latest release with the record sequence
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** the `cli` leg looks up the latest greeter-cli release tag and its commit sha with `gh`, then runs `bin/cli-release fetch`, `ruby-version`, `ruby/setup-ruby` with the declared Ruby, `install` with a launcher, and `ruby/setup-ruby` with the suite's Ruby, in the order of `record.yml`, and every step that sets `GH_TOKEN` comes before the `fetch` step and none after it
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Each leg runs its driver spec and writes its own trace
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** each `drivers` leg runs `bundle exec rspec spec/drivers/<channel>_driver_spec.rb` with `--format RepoTraceFormatter` and `REPO_TRACE_PATH=tmp/repo-trace-drivers-<channel>.json`, and uploads `repo-trace-drivers-<channel>` with `retention-days: 1` and `if-no-files-found: error`
- Maps to: `spec/ci_workflow_spec.rb`

### Requirement: CI publishes the merged trace on main and weekly
CI SHALL merge the partial traces in a `trace` job and, on push to `main` and on the
weekly schedule only, and only when every input job succeeded, upload artifact
`repo-trace` and send `repository_dispatch` `docs-refresh` with
`client_payload[repo]=greeter-acceptance` to `greeterhq/greeter-docs`. The input
jobs are `rspec`, `drivers` and `pact`.

#### Scenario: Trace job merges and uploads on main and schedule
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** the schedule is `17 6 * * 1`, `trace` has `needs: [rspec, drivers, pact]`, `if: ${{ !cancelled() }}`, `permissions: {contents: read}`, a checkout with `persist-credentials: false`, downloads each of the four partial artifacts (`repo-trace-spec`, `repo-trace-drivers-cli`, `repo-trace-drivers-http`, `repo-trace-pact`) by name with neither `run-id` nor `merge-multiple`, runs `bin/merge-repo-trace` on all four only when `needs.rspec.result`, `needs.drivers.result` and `needs.pact.result` are all `success`, uploads `repo-trace` with `retention-days: 90` only on the gate (`github.event_name == 'schedule' || (github.event_name == 'push' && github.ref == 'refs/heads/main')`), and ends with a step that fails the job when an input job did not succeed
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Notify-docs dispatches docs-refresh
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `notify-docs` has `needs: trace`, `permissions: {}`, the same gate, a token from `actions/create-github-app-token@v3` (client-id `vars.DISPATCH_APP_CLIENT_ID`, private-key `secrets.DISPATCH_APP_PRIVATE_KEY`, owner `greeterhq`, repository `greeter-docs` only, `permission-contents: write`), and a `docs-refresh` dispatch with `client_payload[repo]=greeter-acceptance` that reads the token from `GH_TOKEN` in `env`
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Failed runs and pull requests publish nothing
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** the gate excludes `pull_request`, and `notify-docs` depends on `trace`, which fails when `rspec`, `drivers` or `pact` failed, so a red run on `main` uploads no `repo-trace` and sends no `docs-refresh`
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Workflow credentials are least-privilege
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** the workflow has top-level `permissions: {contents: read}`, and no `run:` step of `trace` or `notify-docs` contains a `${{` expression
- Maps to: `spec/ci_workflow_spec.rb`

#### Scenario: Main and weekly runs do not cancel each other
- **WHEN** `.github/workflows/ci.yml` is parsed
- **THEN** `concurrency.group` is `ci-${{ github.event_name }}-${{ github.ref }}` and `cancel-in-progress` is `${{ github.event_name == 'pull_request' }}`
- Maps to: `spec/ci_workflow_spec.rb`

### Requirement: Record mode notifies docs after publishing
`record.yml` SHALL run a `notify-docs` job after `publish`, only when every
`publish` leg succeeded. For each ledger environment of the run it SHALL send one
`repository_dispatch` `docs-refresh` to `greeterhq/greeter-docs` with
`client_payload[repo]=greeter-acceptance` and `client_payload[ledger]=<environment>`.
The job SHALL mint its own `greeterhq-dispatch` token and SHALL NOT use the
ledger-writer token or run inside `publish`.

#### Scenario: Notify-docs follows a successful publish, once per environment
- **WHEN** `.github/workflows/record.yml` is parsed
- **THEN** `resolve` has an `environments` output, and `notify-docs` has `needs: [resolve, publish]`, `if: always() && needs.publish.result == 'success'`, `permissions: {}`, `strategy.fail-fast: false`, a matrix over `fromJSON(needs.resolve.outputs.environments)`, and sends `docs-refresh` with `client_payload[repo]=greeter-acceptance` and `client_payload[ledger]` taken from `env`, never from a `${{` expression in `run:`
- Maps to: `spec/record_workflow_spec.rb`

#### Scenario: The environments output lists each environment once
- **WHEN** `bin/resolve` output with a matrix of several channels in two environments is turned into the `environments` output with the workflow's Ruby one-liner
- **THEN** the result is a JSON array with each environment once
- Maps to: `spec/record_workflow_spec.rb`

#### Scenario: Notify-docs uses its own token
- **WHEN** `.github/workflows/record.yml` is parsed
- **THEN** `notify-docs` mints its token with `actions/create-github-app-token@v3` using `vars.DISPATCH_APP_CLIENT_ID`, `secrets.DISPATCH_APP_PRIVATE_KEY`, owner `greeterhq`, repository `greeter-docs` only and `permission-contents: write`, passes it as `GH_TOKEN` in `env`, and refers to no `LEDGER_APP` variable or secret
- Maps to: `spec/record_workflow_spec.rb`

#### Scenario: The publish job is unchanged
- **WHEN** `.github/workflows/record.yml` is parsed
- **THEN** `publish` has no dispatch step, no `DISPATCH_APP` reference and the same `permissions` as before, and the only token it mints is the ledger-writer token for `greeter-acceptance`
- Maps to: `spec/record_workflow_spec.rb`
