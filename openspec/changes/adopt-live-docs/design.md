## Context

greeter-docs will read, per repo, requirement slugs and test statuses. The slug
rule and the `greeterhq.repo-trace.v1` schema are shared by every greeterHQ repo.
This design follows `../greeter-core/openspec/changes/adopt-live-docs` and records
only where greeter-acceptance differs. Where this document says "as in greeter-core",
the greeter-core design is the reference and applies unchanged.

Observed in this repo:
- RSpec files live directly under `spec/` and `spec/drivers/`;
  `spec/drivers/greeter_driver_contract.rb` is a shared-example file included by
  `cli_driver_spec.rb` and `http_driver_spec.rb`. `spec/spec_helper.rb` already
  requires every `spec/support/**/*.rb`, so a formatter placed there loads without
  editing `spec_helper.rb` or `.rspec`.
- `features/greeting.feature` has five scenarios tagged `@requirement-greeting-*`
  and `@scenario-*` (for example `@requirement-greeting-count @scenario-count-new-guest`).
  The `@scenario-*` values and scenario names differ from the spec scenario headings.
- `ci.yml` has only `lint` and `spec-gate`; no job runs RSpec. The driver specs need a real channel (`GREETER_CLI_CMD` for cli, `GREETER_BASE_URL` for http). `record.yml` has
  `resolve`, `run` and `publish` (a matrix over environment and channel).
  `tmp/traceability.json` is written by `features/support/hooks.rb`.
- `bin/guard-test-edits` blocks edits under `spec/` and `features/` unless
  `tmp/allow-test-edits` exists.

## Decisions

### Slug helper and tags (as in greeter-core)
`spec/support/repo_trace/slug.rb` defines `RepoTrace::Slug.call(text)`:
`text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')`. `slug_spec.rb`
asserts a hand-written table plus a hand-written slug for every real requirement and
scenario heading in `openspec/specs/**` and in this change's delta (not computed
with the function under test). Tagging, the tag-only diff check
(`spec/support/repo_trace/tag_only_diff.rb`, tagged context wrappers around unchanged
`it_behaves_like` lines) and the file-scoped RuboCop exclusions are done as in
greeter-core. Tag-only rules here: allowed changes in existing files are tag pairs,
whitespace and tagged context wrappers; `spec/spec_helper.rb` is not edited.

### Tag map for greeting
`openspec/requirement-tags.yml`:

```yaml
a-channel-greets-a-valid-guest: greeting-happy
a-channel-rejects-an-invalid-name: greeting-invalid
a-counting-channel-records-the-greeting-count: greeting-count
a-counting-channel-increments-the-count-for-a-returning-guest: greeting-returning
an-idempotent-replay-does-not-double-count: greeting-idempotent
```

The five headings in `openspec/specs/greeting/spec.md` give exactly these slugs
(checked against the headings; no key needed correcting). Values are the suffix
of `@requirement-<value>`.

### Trace-check
`RepoTrace::Check` as in greeter-core (static scan, same heading regexes,
in-flight `ADDED`/`MODIFIED` deltas, archive skipped), with these additions:
- Tags in `spec/**/*.rb` are scanned with the same regex and excluding
  `spec/fixtures/**`.
- Cucumber tags are read from `features/**/*.feature` with
  `@requirement-([a-z0-9-]+)`.
- A requirement whose slug is a key in the map is a channel-behaviour requirement:
  it passes when some Cucumber scenario carries its mapped tag, and it needs no RSpec
  tag. Every other requirement needs an RSpec tag, as before.
- Every `@requirement-*` value in `features/` must be a value in the map, and every
  map key must be a heading slug (problems name the tag or key and its file).
- Scenario slugs are checked for RSpec tags only. The `@scenario-*` tags are not
  compared with heading slugs (they differ and must not be renamed). A scenario with
  no Cucumber counterpart, such as "Channel without counting records not applicable",
  is covered by the capability-gated scenario, as the scenario-traceability rule says.
- Problem strings: as in greeter-core, plus
  `requirement "<slug>" (<spec.md>) maps to tag "<tag>" carried by no Cucumber scenario`,
  `tag "<tag>" (<file>) is not in openspec/requirement-tags.yml`, and
  `map key "<slug>" (openspec/requirement-tags.yml) matches no requirement heading`.
- The real-repo example passes `spec_glob: 'openspec/specs/**/spec.md'`,
  `change_glob: 'openspec/changes/**/specs/**/spec.md'`, `example_glob: 'spec/**/*.rb'`,
  `exclude_glob: 'spec/fixtures/**/*'`, `feature_glob: 'features/**/*.feature'` and
  `tag_map: 'openspec/requirement-tags.yml'`.

Choice made here: "mapped tag carried by at least one scenario" is checked, not
"exactly one". The scenario-traceability rule already requires one Cucumber scenario
per spec scenario, so a count check would duplicate it; revisit if drift appears.

### Capabilities that need RSpec tags
All six capabilities are covered: `greeting` through the tag map; `driver-contract`, `traceability`,
`ledger-publication`, `acceptance-gate`, `environment-targets` and `live-docs-traceability` through RSpec tags.
`harden-candidate-install` is applied, released as v0.3.0 and archived before this change is applied, and this
branch is rebased on `main`, so its requirements are ordinary main-spec requirements. The `change_glob` rule
still handles any other in-flight change.

### Formatter
`spec/support/repo_trace_formatter.rb` (`RepoTraceFormatter`) as in greeter-core:
registered for `:example_passed, :example_failed, :example_pending, :dump_summary`;
statuses passed, failed, pending, skipped; results are `{requirement, scenario, status,
source: 'rspec', location}` sorted by location, requirement, scenario; duplicates
from shared examples collapse keeping the worst status; values validated before writing
(slug `\A[a-z0-9]+(-[a-z0-9]+)*\z`, location `\Aspec/[\w./-]+\.rb:\d+\z`, sha
`\A[0-9a-f]{40}\z`, run_id `\A\d+\z`), errors name the field only; `git rev-parse HEAD`
runs through an argument array. Differences:
- `repo` is `greeter-acceptance`.
- It does not touch `tmp/traceability.json`. `run_id` comes from `GITHUB_RUN_ID` only
  (not `GREETER_RUN_ID`, whose value `<run>-<attempt>` is not digits).
- Shared-example results use the inclusion line as their location (see Shared-example location).
- It writes only when selected with `--format RepoTraceFormatter`, so the default run
  and record mode are unaffected.
- Spec fixtures under `spec/fixtures/repo_trace/` are run in a subprocess, as in
  greeter-core; the fixture spec also asserts that a pre-existing
  `tmp/traceability.json` is left byte-identical.

### Merge script
`bin/merge-repo-trace OUT IN...` is copied from greeter-cli (with `spec/support/repo_trace/document.rb`,
which it requires) and extended from two inputs to one or more (at least two in CI). Same checks:
every input fully validated before comparing; validation fixes `schema` (`greeterhq.repo-trace.v1`) and
`repo` (`greeter-acceptance`), so valid inputs cannot differ in them and only `sha` and `run_id` are compared
across inputs (`null` equals only `null`); no `(requirement, scenario, location)` duplicated across inputs; the
later `recorded_at`; results sorted; nothing written on any error; messages never echo input values. The
repo name in `document.rb` becomes `greeter-acceptance`. Standard library only, `# frozen_string_literal: true`,
run in CI without a bundle. It is not part of any gem (this repo has none), and `lib/` is untouched.
`spec/bin/repo_trace_merge_spec.rb` runs it as a subprocess, the way CI calls it.

### Shared-example location
The driver contract is included by `cli_driver_spec.rb` and `http_driver_spec.rb`. Per the request, the
formatter records, for an example that comes from shared examples, the location of the `it_behaves_like`
line (greeter-cli's rule), so cli and http results never collide. The greeter-cli formatter file read while
planning uses `example.location` and no inclusion backtrace, so the rule must be re-read in greeter-cli at
apply; the planned implementation takes the first frame of `metadata[:shared_group_inclusion_backtrace]`
inside `spec/`, falling back to `example.location`. The location still has to match `\Aspec/[\w./-]+\.rb:\d+\z`.

### Tagging the driver contract
A single wrapper context around an `it_behaves_like` can carry only one requirement/scenario pair, but the
contract file covers five requirements (port surface, capability declaration, neutral outcomes, count
observability, build information; scenarios are in `driver-contract`). So the contract's own `describe`
groups (and examples where one group spans scenarios) get `requirement:`/`scenario:` metadata, which the
tag-only rule allows. Where a single `it_behaves_like` maps to a single pair, it is wrapped in a tagged
context as the shared rules say. Tags never change an assertion, name or body.

### ci.yml
- `on:` adds `schedule: - cron: '17 6 * * 1'`; top-level `permissions: {contents: read}`.
- `concurrency`: `group: ci-${{ github.event_name }}-${{ github.ref }}`,
  `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`. Push runs no longer cancel earlier
  push runs on the same ref (the existing behaviour cancelled them); only pull-request runs cancel.
- Gate (used for uploads and `notify-docs`):
  `github.event_name == 'schedule' || (github.event_name == 'push' && github.ref == 'refs/heads/main')`.
- `rspec` (`needs: lint`, `permissions: {contents: read}`): checkout, `ruby/setup-ruby` with bundler cache,
  `REPO_TRACE_PATH=tmp/repo-trace-spec.json bundle exec rspec --exclude-pattern 'spec/drivers/**/*_spec.rb' --format progress --format RepoTraceFormatter`,
  then `actions/upload-artifact` `repo-trace-spec`, `retention-days: 1`, `if-no-files-found: error`.
  The file is a partial trace.
- `drivers` (`needs: lint`, `permissions: {contents: read}`, `strategy: {fail-fast: false, matrix: {channel: [cli, http]}}`):
  - `http`: a step reads `environments.stage.channels.http.base_url` from `config/environments.yml` with
    Ruby's `YAML` (through the repo's environment-target code when it can be called without a bundle; to be
    settled at apply) and writes `GREETER_BASE_URL` to `$GITHUB_ENV`. The host must pass the same
    `host_pattern` check as record mode before any request. The driver's synthetic header stays on.
  - `cli`: steps copied from `record.yml`'s `run` job in the same order and with `if: matrix.channel == 'cli'`:
    look up the latest release (`gh release view --repo greeterhq/greeter-cli --json tagName`) and its commit
    (`gh api repos/greeterhq/greeter-cli/commits/<tag> --jq .sha`), `bin/cli-release fetch`, `bin/cli-release ruby-version`,
    `ruby/setup-ruby` for that Ruby, `bin/cli-release install --launcher`, then `ruby/setup-ruby` for the suite's Ruby.
    Only the lookup step carries `GH_TOKEN` (`github.token`), and it runs before `fetch`; no step after `fetch` has a token
    (record.yml's later "published at" lookup is not copied). The tag and sha are passed through `env`/step outputs,
    never interpolated into `run:`. As in record.yml, the suite's Ruby is set up first (for both legs), so `fetch` and
    `ruby-version` never depend on the runner image's Ruby; the cli leg then sets up the Ruby the release
    declares for the install and goes back to the suite's Ruby before the driver spec runs.
  - Each leg: `GREETER_CHANNEL`, then
    `REPO_TRACE_PATH=tmp/repo-trace-drivers-<channel>.json bundle exec rspec spec/drivers/<channel>_driver_spec.rb --format progress --format RepoTraceFormatter`
    (`<channel>` through `env`), then upload `repo-trace-drivers-<channel>` with `retention-days: 1`, `if-no-files-found: error`.
  - Weekly, push and pull-request runs all reach the stage http target; accepted.
- `trace` (`needs: [rspec, drivers]`, `if: ${{ !cancelled() }}`, `permissions: {contents: read}`): checkout
  (`persist-credentials: false`), `ruby/setup-ruby` without bundler cache, download the three artifacts by
  name into separate directories (no `run-id`, no `merge-multiple`) and run `bin/merge-repo-trace tmp/repo-trace.json ...`,
  both only when `needs.rspec.result == 'success' && needs.drivers.result == 'success'`. Upload `repo-trace`
  (`retention-days: 90`, `if-no-files-found: error`) when the gate also holds. A last step with
  `if: needs.rspec.result != 'success' || needs.drivers.result != 'success'` runs `exit 1`, so `trace` is red whenever
  an input was, and `notify-docs` (which needs `trace`) is skipped. Merging also runs on pull requests, so a merge
  problem shows before `main`; nothing is uploaded there.
- `notify-docs`: `needs: trace`, `if: <gate>`, `permissions: {}`. Steps: `actions/create-github-app-token@v3`
  (`client-id: ${{ vars.DISPATCH_APP_CLIENT_ID }}`, `private-key: ${{ secrets.DISPATCH_APP_PRIVATE_KEY }}`,
  `owner: greeterhq`, `repositories: greeter-docs`, `permission-contents: write`); then
  `gh api repos/greeterhq/greeter-docs/dispatches -f event_type=docs-refresh -f 'client_payload[repo]=greeter-acceptance'`
  with `GH_TOKEN` from the step output in `env`. No fallback if credentials are missing.
- `spec-gate` still needs only `lint`. The diagram comment at the top is updated.
- `spec/ci_workflow_spec.rb` parses the file with `YAML.safe_load` (`"on"` loads as a string key) and asserts the
  structure above, including that no `run:` step of `trace` or `notify-docs` contains `${{`, and the order of token
  steps against `fetch`.

### record.yml
`notify-docs` is a new job, separate from `publish`:
- `needs: [resolve, publish]`, `if: always() && needs.publish.result == 'success'`,
  `permissions: {}`. `needs.publish.result` is `success` only when every matrix leg
  succeeded; it is `skipped` when there was no work, so nothing is sent then.
- It has `strategy.fail-fast: false` and is a matrix over the distinct ledger environments of the run:
  `environment: ${{ fromJSON(needs.resolve.outputs.environments) }}`. `resolve`
  gains an output `environments` (a JSON array of the distinct `environment` values
  in the resolved matrix, built by the existing Ruby one-liner pattern). `resolve` is
  added to `needs` only to read that output; the request named `publish` alone.
- Steps: mint the token with `actions/create-github-app-token@v3`
  (`vars.DISPATCH_APP_CLIENT_ID`, `secrets.DISPATCH_APP_PRIVATE_KEY`, `owner: greeterhq`,
  `repositories: greeter-docs`, `permission-contents: write`), then
  `gh api repos/greeterhq/greeter-docs/dispatches -f event_type=docs-refresh -f 'client_payload[repo]=greeter-acceptance' -f "client_payload[ledger]=$ENVIRONMENT"`.
  `GH_TOKEN` and `ENVIRONMENT` (`${{ matrix.environment }}`) come through `env`.
  `matrix.environment` is validated by `bin/resolve` against `config/environments.yml`
  before it reaches the matrix.
- No checkout, no `environment: ledger`, no `LEDGER_APP_*` reference. `publish` is not
  edited. The job has no concurrency group: a refresh is idempotent.
- `spec/record_workflow_spec.rb` asserts the structure and that `publish` still mints only
  the ledger-writer token and has no dispatch step.

### What greeter-docs receives
CI: artifact `repo-trace` (RSpec results for tooling requirements, from three jobs) and
`docs-refresh {repo}`. Record mode: `docs-refresh {repo, ledger}`; `greeting`
results are read from the ledger branch. No Cucumber result is added to the repo trace.

### Examples left untagged by design
An example carries a `requirement:`/`scenario:` pair only when it verifies a scenario of a requirement. These do not, and stay untagged:
- every example in `spec/tag_only_diff_spec.rb` (the tag-only check is a tool for this change; the delta has no requirement for it);
- in `spec/capability_gating_spec.rb`, "runs a scenario with no capability tag" and "leaves the repository tmp/traceability.json alone";
- in `spec/workflow_token_order_spec.rb`, the two "has at least one job that installs a candidate" guards;
- in `spec/trace_check_spec.rb`, the examples that check the tag map's completeness are tagged (to "The requirement-tag map covers the greeting headings"); only the tag-only diff examples are untagged.

## Security considerations

Reviewed: formatter, trace-check, both workflow edits and the cross-repo dispatch.
Trust boundaries: pull-request code (no secrets) versus `main`, schedule and record
mode (have the dispatch key); the trace file and dispatch payload (read by greeter-docs).

| # | Finding | Severity | Resolution |
|---|---|---|---|
| S1 | `ci.yml` has no top-level `permissions`, so jobs get the repository default token scope. | Medium | Add top-level `permissions: {contents: read}`; `notify-docs` has `{}`. |
| S2 | The app token could carry every permission the app has on greeter-docs. | Medium | `permission-contents: write` only, one repository `greeter-docs`, owner `greeterhq`, minted in the job that uses it. |
| S3 | Trace values end up in a file greeter-docs renders. | Medium | Formatter validates slug, location, sha and run_id patterns, writes only whitelisted keys, raises without writing on a violation. |
| S4 | `client_payload[ledger]` is derived from workflow input and event payload in record mode. | Medium | It comes from `matrix.environment`, which `bin/resolve` validates against committed config; it reaches `gh` only through `env`, never interpolated into `run:`. |
| S5 | The dispatch token must not be the ledger-writer token, and the ledger-writer token must not reach a dispatch job. | Medium | Separate app (`greeterhq-dispatch`), separate job, no `LEDGER_APP_*` in `notify-docs`, no `DISPATCH_APP_*` in `publish`; both asserted in `record_workflow_spec`. |
| S6 | A tag in a comment or string can fool the regex scan. | Low, accepted | Same as greeter-core; fixtures excluded. |
| S7 | Actions are referenced by major tag, including the one holding the private key. | Low, accepted | `@v3` as in `publish`; pinning belongs to a dependency-scanning change. |
| S8 | Consumer side: greeter-docs must allowlist `client_payload[repo]` and `[ledger]` and validate the schema. | Info | Out of scope here; recorded for the greeter-docs change. |
| S9 | Missing dispatch credentials fail `notify-docs`. | None | Intended; no fallback. |
| S10 | The cli leg runs a downloaded release. | Medium | Same controls as record mode: checksum and tag check in `bin/cli-release fetch`; the only token (`github.token`, `contents: read`) is used before `fetch` and none after; the job has no write permission and no dispatch secret. |
| S11 | `trace` runs repo code on every event, including pull requests. | Low | Read-only permissions, `persist-credentials: false`, same-run downloads by name, upload only on the gate; no secrets. |

No secret is written to the repo, logs or artifacts. The trace holds slugs, statuses,
locations and run metadata only.

## Risks / trade-offs
- `notify-docs` fails until the credentials and app installation exist (maintainer,
  before merge). In record mode a failing `notify-docs` does not affect the recorded
  ledger; it is a separate job after `publish`.
- If one environment's `publish` fails, no environment is notified in that run, because
  the condition is on the whole job result. Accepted: the next run refreshes.
- `greeting` results appear in docs one ledger refresh later than RSpec results.
- Tags may push `it` lines over RuboCop's line length; wrapping is allowed.

## Open points
- Contract tagging: one wrapper context cannot carry five requirements, so the contract's own groups carry the
  tags (see Tagging the driver contract). Confirm.
- The shared-example location rule must be re-checked in greeter-cli at apply (see Shared-example location).
- The cli leg reads another repository's latest release with `github.token`. This works if `greeterhq/greeter-cli`
  is readable by that token. If it is private, a different token is needed, which would change the token rules.
- With the requested concurrency, pushes to the same ref no longer cancel earlier push runs.

## Follow-up
- A Cucumber repo-trace writer (`source: cucumber`, as greeter-http has) would put
  `greeting` results into the repo trace. It needs suite code and a new suite tag, so
  it is not part of this change.
