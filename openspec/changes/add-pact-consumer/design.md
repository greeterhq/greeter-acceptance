# Design

## Context

See proposal.md (Why) for the motivation. The requirements are in
`specs/pact-consumer/spec.md` and `specs/live-docs-traceability/spec.md`.

Facts this design rests on, checked against the code:

- **greeter-http** (`lib/greeter_http/adapters/`):
  - `JsonPresenter#present_count` returns the body
    `{"guest_name", "greeting", "count", "greeted_at"}`. `greeted_at` is
    `Time#utc.iso8601`, for example `2026-01-01T12:00:00Z`.
  - `RackApp` answers 201 for a new greeting and 200 for a replay. Every error
    body is `{"error": <code>, "message": <string>}`. An empty name is 422
    `invalid_name`, with its message taken from the core. A missing key is 400
    `missing_idempotency_key`.
  - `VersionHeaders` sends `x-greeter-version` and `x-greeter-core-version` in
    lowercase. Pact compares header names without regard to case.
- **HttpDriver** (`lib/greeter_acceptance/drivers/http_driver.rb`):
  - It sends `Content-Type: application/json`, `X-Greeter-Synthetic: true` (the
    default) and `Idempotency-Key`. The key is the caller's, or
    `SecureRandom.uuid` when the caller gives none. The body is `{"name": ...}`.
  - It reads `count` and `greeting` from the body and both version headers.
- **pact 2.1.2** (already locked):
  - `require 'pact/rspec'` tags every file under `spec/pact/` with `:pact` and
    runs `filter_run_excluding :pact`.
  - Files under `spec/pact/providers/` get `pact_entity: :consumer`, which pulls
    in `has_http_pact_between`, `new_interaction` and the matchers
    (`match_any_integer`, `match_type_of`, `match_any_string`, `match_regex`,
    `match_uuid`, `match_iso8601`).
  - `interaction.execute { |mock_server| ... }` yields a server with `#url` and
    writes the pact to `pacts/` (the default `pact_dir`) when every interaction
    matched. Writes merge into an existing file.
- **Trace check** (`spec/support/repo_trace/check.rb`) reads `requirement:` and
  `scenario:` tags from RSpec files as text, so the pact examples count for the
  trace check even though the default run excludes them.

## Goals / Non-Goals

**Goals:**
- A pact that describes exactly what HttpDriver sends and reads, produced by the
  real driver.
- Publication that cannot happen from a pull request, and a broker token that
  exists only in the steps that call the broker.

**Non-Goals:**
- Changing HttpDriver or the port. The pact must fit the driver as it is.
- A Ruby-side Pact Broker client. All broker calls go through `pact-cli`.

## Decisions

### Port and drivers: no change

Before and after this change, the port is:

```ruby
channel                                  # => Symbol
capabilities                             # => Set[Symbol]
supports?(capability)                    # => Boolean
greet(name, idempotency_key: nil)        # => GreetResult(message, guest_name, count, outcome)
count_for(name)                          # => Integer | nil
last_error                               # => Symbol | nil
last_native_error                        # => Object | nil
native_idiom_for?(error)                 # => Boolean
build_info                               # => BuildInfo(channel_version, core_version) | nil
```

This change adds no port method. CliDriver and HttpDriver are unchanged.

### The 400 missing-key response is not in the contract

HttpDriver never sends a request without `Idempotency-Key`. `post_greeting`
sets `idempotency_key || SecureRandom.uuid`. A consumer pact records what the
consumer depends on. An interaction the consumer can never produce would force
greeter-http to keep a response no client reads. It would also have to be sent
by something other than the driver, so it would stop being a contract of
HttpDriver. HttpDriver does not read the 400 body either: any status other than
200, 201 or 422 becomes `:infrastructure_error`. Keeping the 400 is
greeter-http's own concern, and its own tests cover it.

Alternatives considered:
- Send the request from the spec with plain `Net::HTTP`. This was rejected
  because the result would not be a contract of the driver.
- Add a way for the driver to omit the key. This was rejected because it
  changes driver behaviour only to satisfy the pact.

### The driver comes from the composition root

The spec calls
`CompositionRoot.build_driver(env: { 'GREETER_CHANNEL' => 'http', 'GREETER_BASE_URL' => mock_server.url })`.
That method already takes an `env:` hash, so the process `ENV` is never
changed, and the rule that only the composition root constructs drivers still
holds.

### Interaction shapes

The request headers are the same in every interaction:

| Header | Value |
|---|---|
| `Content-Type` | `application/json` (exact) |
| `X-Greeter-Synthetic` | `true` (exact) |
| `Idempotency-Key` | `match_uuid` (the driver generates the key), or exactly `0b0e3a52-6f1c-4b8e-9d2a-2f3c1e4d5a6b` in the replay state |

The request body is exact: `{"name":"ada"}` or `{"name":""}`. These are the
values the consumer sends, so they are not provider-chosen.

| State | Status | Response body | Response headers |
|---|---|---|---|
| `no greetings for ada` | 201 | `guest_name: match_type_of('ada')`, `greeting: match_type_of('Hello, ada!')`, `count: match_any_integer(1)`, `greeted_at: match_iso8601('2026-01-01T12:00:00Z')` | `X-Greeter-Version`, `X-Greeter-Core-Version`: `match_regex(/^\d+\.\d+\.\d+$/, '1.0.0')` |
| `ada has been greeted with key 0b0e3a52-…` | 200 | same matchers, `count` example `1` | same |
| `any state` | 422 | `error: 'invalid_name'` (exact: a code is part of the contract), `message: match_any_string` | none required |

`count` uses `match_any_integer`, which is the V3 `integer` matcher, not
`match_type_of`. A type matcher accepts any JSON number, so `count: 1.0` would
still pass. The integer matcher fails it. With this matcher, provider
verification fails if `count` is renamed or removed (the key is missing) or
retyped (string, float or null).

The 422 interaction declares no version headers. The driver does read them on
any response, but `build_info` would only need them on a probe, which this spec
does not trigger. Keeping the interaction small keeps the contract to what is
used on that path.

### Spec layout and ordering

There is one file, `spec/pact/providers/greeter_http_spec.rb`, with one
top-level group declared `has_http_pact_between 'greeter-acceptance', 'greeter-http'`
and run with `order: :defined`:

1. `before(:context)` deletes `pacts/greeter-acceptance-greeter-http.json`, so a
   local re-run never merges stale interactions into the file that gets
   published.
2. Three examples, one per interaction. Each calls the driver inside `execute`
   and checks the neutral outcome (greeted, or last error `:invalid_name`).
3. A final group reads the written pact file. It checks that there are exactly
   three interactions, that every request carries the synthetic header and a
   key, and that the `$.count` rule is an integer matcher with no exact
   `count`, `greeted_at` or version value. This group covers the
   "contract holds only…" and "matched by type or pattern" requirements.

Each example carries `requirement:` and `scenario:` tags from
`specs/pact-consumer/spec.md`.

### Default exclusion

`spec/spec_helper.rb` adds `config.filter_run_excluding :pact`, and the pact
spec file does `require 'pact/rspec'`. The exclusion lives in `spec_helper`, not
only in the gem, so it applies even when the gem is not loaded, and the default
run still skips any `:pact` example. RSpec drops a configured exclusion when the
same tag is passed with `-t`, so `-t pact` runs these examples. The `rspec`
CI job's command stays as it is.

### CI jobs

```
lint ──┬── spec-gate
       ├── rspec ──────┐
       ├── drivers ────┼── trace ── notify-docs
       └── pact ───────┘
              └── pact-publish     (push to main, or push of a v* tag)
```

- **`pact`**: has `needs: lint`, `permissions: {contents: read}`, a checkout
  with `persist-credentials: false`, and the suite's Ruby with
  `bundler-cache`. It runs on every trigger and references no secret. It runs:

  ```
  REPO_TRACE_PATH=tmp/repo-trace-pact.json bundle exec rspec -t pact spec/pact/providers --format progress --format RepoTraceFormatter
  ```

  It uploads `repo-trace-pact` (1 day, `if-no-files-found: error`) and `pacts`
  (1 day, `if-no-files-found: error`).
- **`trace`**: has `needs: [rspec, drivers, pact]`. It adds a download of
  `repo-trace-pact` to `tmp/traces/pact`, adds that file to the
  `bin/merge-repo-trace` call, and adds `needs.pact.result == 'success'` to
  every guard and to the final failing step. `bin/merge-repo-trace` already
  accepts any number of inputs, and pact results have `source: rspec` and
  locations under `spec/`, so the merge needs no change.
- **`pact-publish`**:
  - **Gate:** it has `needs: pact` and
    `if: github.event_name == 'push' && (github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v'))`.
    A pull request or a schedule never satisfies it.
  - **Permissions and checkout:** it has `permissions: {contents: read}` and
    `actions/checkout` with `fetch-depth: 0` and `persist-credentials: false`.
    The full fetch brings `origin/main` with no second, authenticated fetch.
  - **Download:** it downloads the `pacts` artifact from this run.
  - **Tag check:** on a tag only, it runs
    `git merge-base --is-ancestor "$GITHUB_SHA" origin/main`, which exits
    non-zero when the tag is off main. The check runs before any step that has
    the token.
  - **Publish:** it runs
    `docker run --rm -e PACT_BROKER_BASE_URL -e PACT_BROKER_TOKEN -v "$PWD/pacts:/pacts" pactfoundation/pact-cli:<pinned> pact-broker publish /pacts --consumer-app-version "$GITHUB_SHA"`.
    On main it adds `--branch main`. On a tag it adds neither `--branch` nor
    `--tag`. Publishing is idempotent for the same SHA and content, so a tag on
    a commit already published from main is harmless.
  - **Record deployments:** on a tag only, it runs two steps:
    `pact-broker record-deployment --pacticipant greeter-acceptance --version "$GITHUB_SHA" --environment stage`,
    then the same with `--environment prod`.
  - **Token scope:** each `pact-broker` step sets
    `PACT_BROKER_BASE_URL: ${{ vars.PACT_BROKER_BASE_URL }}` and
    `PACT_BROKER_TOKEN: ${{ secrets.PACT_BROKER_TOKEN }}` in its own `env:`.
    `run:` uses only `$GITHUB_SHA` and the env names, never `${{`.
  - **Image pin:** the image is pinned as
    `pactfoundation/pact-cli:<tag>@sha256:<digest>` in a workflow env
    `PACT_CLI_IMAGE`, matching how `OPENSPEC_VERSION` is pinned. During apply,
    pick the latest release tag and read its digest with
    `docker buildx imagetools inspect pactfoundation/pact-cli:<tag>`. Then
    record both in the "Pinned pact-cli image" section below.

Publishing runs in a separate job so the token never shares a runner with the
pact specs, the gem's native FFI library, or `bundle install`. Running the
specs in the publish job was rejected for that reason. The publish job installs
no gems.

The suite-tag deployment records exist because the channel gates run a suite
tag (`ACCEPTANCE_REF`). The pact at that tag is what stage and prod are tested
against.

### Verifying the workflow

The workflow is checked as parsed YAML in `spec/ci_workflow_spec.rb`, in the
existing style. The "tag off main" scenario is also checked by behaviour. The
spec takes the ancestry step's `run:` text and runs it with `GITHUB_SHA` set, in
a temporary repo built with the existing `GitHelpers`. That repo has an
`origin/main` and a commit off main. The step must exit 0 for the commit on main
and non-zero for the commit off it.

### Proving the pact spec can fail

HttpDriver already fits the contract, so the pact spec may pass on its first
run. To show it is not passing vacuously, the red-test group runs two
temporary mutations:

1. Stop HttpDriver sending `X-Greeter-Synthetic`. The interactions must report
   a request mismatch.
2. Change the `count` matcher in the pact spec to a string. The integer-matcher
   example must fail.

Each mutated file is copied first and restored afterwards. `cmp` against the
copy must show the restored file is byte-identical. The real red tests for this
change are the `ci.yml` examples.

## Risks / Trade-offs

- **[Risk] The version-header regex is stricter than the provider allows.**
  `VersionHeaders::VERSION_PATTERN` accepts `\d+(\.\d+)*([-.][0-9A-Za-z]+)*`, so
  `1.2.3-rc.1` and `1.2` are valid provider values. The consumer expects
  `^\d+\.\d+\.\d+$`. Provider verification will fail the first time greeter-http
  runs a pre-release version or a version with two parts. This is deliberate:
  HttpDriver only promises to report a plain `x.y.z`. **Mitigation:** if
  greeter-http adopts pre-release versions, widen the regex in a new suite
  version. The failure shows up in greeter-http's verification, not in
  production.
- **[Risk] Deployments are recorded before greeter-http verifies the pact.**
  `v0.4.0` is tagged after this change is archived and before greeter-http has
  a provider verification. From then on, the broker shows `greeter-acceptance`
  in stage and prod with an unverified pact. This is safe today because
  greeter-http's `cd.yml` runs no `can-i-deploy`, so nothing reads that state
  yet. **Mitigation:** greeter-http's verification is planned with pending
  pacts enabled, so an unverified pact cannot fail its build. It lands before
  greeter-http's first `can-i-deploy`. If greeter-http adds `can-i-deploy`
  first, its deploys to stage and prod would be blocked until it verifies this
  pact.
- **[Risk] A pact gem upgrade changes the derived metadata or the default
  `pact_dir`.** **Mitigation:** `spec_helper` excludes `:pact` itself. The
  pact-file examples read `pacts/` explicitly, so a moved directory fails them.
  The gem is pinned `~> 2.1` and locked.
- **[Trade-off] `match_iso8601` uses the gem's loose pattern.** The pattern is
  `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)*(.\d{2}:\d{2})*`. It accepts the
  provider's `Z` form and also some strings that are not strict ISO-8601. That
  is enough to catch a rename or a retype, which is what the requirement asks
  for.
- **[Trade-off] PR runs pay for an extra job.** The pact job is small (no
  network, three interactions) and gives PRs a trace with the pact results.

## Security considerations

This is a review of the planned `ci.yml` changes and the pact spec. Here is
what the plan exposes:
- **One credential:** `PACT_BROKER_TOKEN`, which can publish pacts and record
  deployments.
- **One external endpoint:** `vars.PACT_BROKER_BASE_URL`.
- **One container:** the third-party `pactfoundation/pact-cli` image, which
  runs with that token.

Findings are ordered by severity. Each finding marked "Task" has a task in
tasks.md.

### S1 (high): any same-repo branch can read the broker token

**Issue.** `PACT_BROKER_TOKEN` is a repository secret. GitHub gives repository
secrets to every workflow run except runs from forks. That includes
`pull_request` runs from a branch in this repo and pushes to any branch.
Anyone who can push a branch can change `ci.yml` on that branch so that a step
prints or sends the token. The `if:` gate and the step-level `env:` only limit
where the unchanged workflow uses the token. They do not limit who can read it.
So the requirements "the broker token reaches only the publish steps" and "a
pull request publishes no pact" are not enforced against a changed workflow.

**Fix.** Move the token into a GitHub Environment named `pact-broker`, and set
its deployment rule to allow only the `main` branch and `v*` tags.
`pact-publish` declares `environment: pact-broker`. This follows
`record.yml`'s `environment: ledger`. A job on any other ref then cannot get
the secret, even with a changed workflow, because the environment refuses to
run it. Keep `PACT_BROKER_BASE_URL` as an environment variable of that
environment, or as a repository variable.

**Done in settings.** The `pact-broker` environment exists, with deployments
allowed only from `main` and `v*` tags. `PACT_BROKER_TOKEN` has moved into it,
and the repository secret has been deleted.

**Task:** 1.6 and 4.4.

**Related.** The environment rule accepts any `v*` tag, so who can create a tag
matters too. This repo's existing `suite-tags` ruleset already restricts
creating, moving and deleting `v*` tags, so no new ruleset is needed. The
ancestry check still stops a tag on a commit that is not on main.

### S2 (medium): the publish job trusts the pact artifact as-is

**Issue.** `pact-publish` uploads whatever is in the `pacts` artifact. The
`pact` job that produced it ran `bundle install`, the native `pact-ffi`
library and the spec code. If that job is compromised, or if a later spec adds
another pact, the token can publish:
- a pact for any consumer name;
- a pact against another provider;
- extra files.

The broker token can usually write for every pacticipant.

**Fix.** Before any step that has the token, a standard-library Ruby step
checks the downloaded directory:
- it holds exactly one file, `greeter-acceptance-greeter-http.json`;
- the file parses as JSON;
- `consumer.name` is `greeter-acceptance`;
- `provider.name` is `greeter-http`.

If any check fails, the job fails. The artifact is downloaded by name from
this run only, into its own directory, with neither `run-id` nor
`merge-multiple`, as `trace` already does.

**Task:** 1.6 and 4.5.

### S3 (medium): how the token and files reach the container

**Issue.** The token must reach `docker run` by name (`-e PACT_BROKER_TOKEN`).
Writing `-e PACT_BROKER_TOKEN=$PACT_BROKER_TOKEN` would put the value on the
runner's process list, and it could appear in a `set -x` trace. The plan's
command already uses the name-only form, but nothing checks it. A `--verbose`
flag on `pact-broker` logs request headers, including `Authorization`, and
GitHub's masking does not cover every encoding of the value. The `pacts`
directory is mounted read-write, so the container could write back into the
workspace.

**Fix.** These are pinned by the token-scope examples:
- every `docker run` passes the broker variables as `-e NAME` only;
- no `pact-broker` command has `--verbose` or `-v`;
- the mount is `"$PWD/pacts:/pacts:ro"`;
- `docker run` has `--rm`.

**Task:** 1.6 and 4.4.

### S4 (low): the token could go to a non-HTTPS URL

**Issue.** `PACT_BROKER_BASE_URL` comes from `vars`. If it is mistyped as, or
changed to, an `http://` URL, the token is sent in clear text.

**Fix.** The S2 check step also fails unless `PACT_BROKER_BASE_URL` starts with
`https://`. That step reads the URL from `env`, never from `${{` in `run:`.

**Task:** 1.6 and 4.5.

### S5 (low): a tag that does not match VERSION records the wrong deployment

**Issue.** A `v*` tag on main whose name does not match
`GreeterAcceptance::VERSION` would still publish and record stage and prod.
`record.yml` already refuses such a tag, but `pact-publish` does not. The
broker would then show a suite version as deployed that the channel gates
never run.

**Fix.** On a tag, compare `GITHUB_REF_NAME` with `v` + `VERSION`, reading
`lib/greeter_acceptance/version.rb` with standard-library Ruby and no bundler.
Fail before any step that has the token, using the same check `record.yml`
uses.

**Task:** 1.6 and 4.5.

### Reviewed and accepted

- **Fork pull requests** get no secrets, and `ci.yml` uses no
  `pull_request_target`. The token-scope example also asserts that
  `pull_request_target` is absent.
- **The image** is pinned by digest, so a moved tag cannot swap the code that
  sees the token.
- **The pact spec** gets no secret and makes no network call beyond the local
  mock server. The `pacts` artifact holds example values only, no data from
  real guests.
- **The checkout** in `pact-publish` uses `persist-credentials: false`, and the
  job runs no repository code. It only runs `git merge-base` and the
  standard-library checks.
- **GitHub Actions** in `pact-publish` (`checkout`, `download-artifact`) are
  pinned by major tag, like the rest of this repo. Pinning them by commit SHA
  is a repo-wide decision and out of scope here. It is noted for a separate
  change.

## Migration Plan

The settings are done:
- `PACT_BROKER_BASE_URL` is a repository variable.
- `PACT_BROKER_TOKEN` is a secret of the `pact-broker` environment, which
  allows only `main` and `v*` tags. The repository secret has been deleted.
- The existing `suite-tags` ruleset protects `v*` tags.

1. Merge to main. The first publish creates `greeter-acceptance` in the broker.
   If publishing fails, only `pact-publish` goes red. `trace` and `notify-docs`
   do not depend on it.
2. Archive the change.
3. Tag `v0.4.0` on main. That publishes the pact and records stage and prod.
4. greeter-http adds provider verification with pending pacts enabled (outside
   this repo), before its first `can-i-deploy`.

**Rollback:** revert the workflow change. Deployment records already in the
broker can be removed with `pact-broker record-undeployment` for stage and
prod.

## Pinned pact-cli image

Filled in during apply (task 4.1), from
`docker buildx imagetools inspect pactfoundation/pact-cli:<tag>`:

- Tag: `1.5.0.5`, the latest release tag on Docker Hub when this was applied.
  `latest` pointed to the same linux/amd64 and linux/arm64 images.
- Digest: `sha256:77b98079e5be279353f61e116a0b9b3af19e55b215532b30d430ff5df66e5ac9`.
  This is the OCI image-index digest printed as `Digest:`. It covers
  linux/amd64 (`sha256:09a1ae00…5509`) and linux/arm64 (`sha256:b4dd2f80…c7ba`).
- `PACT_CLI_IMAGE: pactfoundation/pact-cli:1.5.0.5@sha256:77b98079e5be279353f61e116a0b9b3af19e55b215532b30d430ff5df66e5ac9`
