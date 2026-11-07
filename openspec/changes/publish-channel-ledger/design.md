# Design

## Context

See proposal.md - Why. Current state, from the code:

- `build_driver` lives in `features/support/env.rb`, which ends in `World(...)`
  and so cannot be loaded outside Cucumber. `bin/` scripts cannot build a driver.
- `env.rb` memoizes the driver on the World (`@driver ||=`). Cucumber builds a new
  World per scenario, so each scenario has its own driver and anything it learns
  is lost. The trace avoids this with a process-wide `$greeter_trace` and an
  `at_exit` write.
- `Trace` (`greeterhq.traceability.v1`) and `Ledger` (`greeterhq.ledger.v1`) are
  status-only. `Ledger#channels` is whatever files were passed in, so nothing
  knows which channels should exist.
- Drivers raise on any unrecognised native result.
- CI is `ci.yml` with lint and spec-gate only. Tag `v0.1.0` exists.

## Goals / Non-Goals

**Goals:**
- One run is attributable to one verified channel version, in one environment,
  under one suite version.
- The ledger converges when channels publish at different times or at once.
- The only job with write access never runs code from a channel under test.

**Non-Goals:**
- Retrying or de-flaking channel calls. A driver reports what happened once.
- Rendering the ledger anywhere other than `LEDGER.md`.
- Per-step results. Scenarios stay single-purpose (see the archived
  `add-neutral-acceptance-suite` design).

## Decisions

### Composition root moves to `lib/` (supersedes an earlier rule)

This **supersedes** the rule from `add-neutral-acceptance-suite` that
`features/support/env.rb` is the only composition root. The new rule: 
`lib/greeter_acceptance/composition_root.rb` is the only place a driver is
constructed; `env.rb` and `bin/*` only call it.

```ruby
# before: features/support/env.rb (reads ENV directly, unloadable outside Cucumber)
GreeterAcceptance.build_driver                    # => driver

# after: lib/greeter_acceptance/composition_root.rb
CompositionRoot.build_driver(env: ENV)            # => raw driver (bin/*, specs)
CompositionRoot.build_observed_driver(env: ENV)   # => raw driver wrapped in Observed
CompositionRoot.channels                          # => %w[cli http]
```

`env.rb` shrinks to a World module that calls `build_observed_driver`. Taking
`env:` as an argument lets `spec/` test it with a plain hash. The rule text is
updated in `openspec/config.yaml`, `README.md`, the `env.rb` comment and
`.kiro/steering/architecture.md`.

`bin/` needs a driver for a pre-flight version check and so that `deployed.json`
can be written even when the suite crashes.

### Port: `build_info` and `infrastructure_error`

```ruby
# before
channel; capabilities; supports?(cap); greet(name, idempotency_key: nil) # => GreetResult
count_for(name); last_error; last_native_error; native_idiom_for?(error)
GreetResult#outcome  # :greeted | :invalid_name
last_error           # :invalid_name | nil

# after (additions marked +)
+ build_info                       # => BuildInfo(channel_version:, core_version:) or nil
GreetResult#outcome  # :greeted | :invalid_name | +:infrastructure_error
last_error           # :invalid_name | +:infrastructure_error | nil
```

`nil` from `build_info` means unobservable. It must not change channel state.

| | CliDriver | HttpDriver |
|---|---|---|
| `build_info` | runs `<cmd> --version`, parses `greeter-cli <v> (greeter-core <v>)` (the format `exe/greeter` prints), caches it; nil if it cannot parse | passive: reads the version headers off each response; if none seen yet, one greet with an invalid name as a probe (422, assumed to change nothing); nil if no headers |
| `infrastructure_error` | spawn failure (e.g. `ENOENT`) or any exit other than 0 and 2 | connection, DNS, TLS or timeout errors, and any status other than 200, 201 and 422 |

Mapping every unrecognised native result to `infrastructure_error` keeps drivers
non-raising. The trade-off: a real contract regression (say the service returns
400 for valid input) shows as `error` rather than `failed`. Both turn the gate
red, so the decision is cheap.

### Observing decorator and run record

Steps may only call the port, and `last_error` is cleared by the next greet, so
an infrastructure error mid-scenario could be lost. `Observed` wraps a driver,
implements the same port, and records every infrastructure error and every
`build_info` it sees. Hooks read it; steps do not know it exists.

```
 BeforeAll  RunRecord.start(env)           suite version, run id, expected version;
                                           probe once with a fresh raw driver
 Before     capability gating (unchanged)
 After      RunRecord.row(tags, status)    status: passed | failed | error
            RunRecord.observe(driver.observations)
 AfterAll   RunRecord.finish -> tmp/traceability.json
```

Scenario status: not applicable if gated; `error` if the decorator saw an
infrastructure error (even if an assertion also failed); otherwise `failed` or
`passed`. `RunRecord` keeps the set of distinct `BuildInfo` seen:

- none: `unobserved`
- one, equal to the expected version: `verified`; different: `mismatch`
- two or more: `inconsistent`

This replaces `$greeter_trace` and `at_exit`. The suite version comes from
`GreeterAcceptance::VERSION`, which the record workflow checks against the tag.

### Schemas

`tmp/traceability.json` and `channels/<channel>.json` share
`greeterhq.traceability.v2`:

```json
{
  "schema": "greeterhq.traceability.v2",
  "run": {
    "channel": "http", "environment": "prod", "suite_version": "v0.2.0",
    "channel_version": "v1.2.3", "channel_sha": "def456", "core_version": "0.1.5",
    "verification": "verified", "recorded_at": "2026-11-06T12:00:00Z",
    "run_id": "123456789", "released_at": null, "forced": null
  },
  "results": [
    { "requirement": "greeting-count", "scenario": "count-new-guest", "status": "passed" }
  ]
}
```

`deployed.json` (`greeterhq.deployed.v1`):

```json
{ "schema": "greeterhq.deployed.v1", "environment": "prod",
  "channels": {
    "cli":  { "version": "v0.1.2", "sha": "abc123", "artifact": "tag", "run_id": "..." },
    "http": { "version": "v1.2.3", "sha": "def456", "run_id": "..." } } }
```

`ledger.json` (`greeterhq.ledger.v2`) holds `suite.version`, a `channels` map
with each column's `state`, `reasons`, versions, `verification`, `recorded_at`
and `run_id`, and a `requirements` map of requirement to per-channel cell status
(`passed`, `failed`, `error`, `not_applicable`, `missing`). `LEDGER.md` renders
the same data with context headers per column. Neither carries a generation
timestamp, keys and rows are sorted, and the channel list is
`CompositionRoot.channels`, so output is a pure function of its inputs. The
requirement list comes from the `@requirement-*` tags in `features/` at the suite
tag being published.

### Column states

For each known channel:

```
 no channels/<c>.json                           -> missing
 suite_version  < ledger suite version          -> stale (reason: suite)
 deployed.json version != result channel_version -> stale (reason: channel)
 neither                                         -> current
```

A requirement with no row in an otherwise present result is a `missing` cell,
never `not_applicable`. `verification` is shown beside the state but does not
change it. If a run produces no result at all (for example the artifact download
fails), publish still updates `deployed.json`, so that column becomes stale
because the deployed version moved on.

### Environment configuration

```yaml
# config/environments.yml, read from the default branch
environments:
  prod:
    ledger_branch: ledger-prod
    channels:
      http:
        base_url: https://<api-id>.execute-api.<region>.amazonaws.com
        host_pattern: '\A[a-z0-9]+\.execute-api\.<region>\.amazonaws\.com\z'
      cli:
        repo: greeterhq/greeter-cli      # artifact source; exact match
  stage:
    ledger_branch: ledger-stage
    channels: { ... }
```

The event names an `environment`; the URL and the artifact repository are looked
up here and the host is matched against `host_pattern` before any request.

### Workflows

**Record** (`record.yml`: `repository_dispatch: channel-released`, tag push
`v*`, `workflow_dispatch` with the event's fields plus `rerun_all` and `force`)
has three stages:

```
 resolve   default-branch code   validate event, read config, find latest suite
                                 tag, build the matrix (from deployed.json for a
                                 new tag or rerun_all)
 run       contents: read        checkout the tag with persist-credentials: false;
                                 fetch + verify the artifact (checksum, tag -> sha);
                                 run the suite; upload the result as an artifact
 publish   contents: write       checkout the tag; stdlib Ruby only, no bundle
                                 install; treat the artifact as data; regenerate;
                                 push the ledger branch
```

The token is not in the environment of any step that executes downloaded code.
`publish` runs with `!cancelled()` so that an errored run still updates
`deployed.json`.

**Gate** (`gate.yml`, `workflow_call`, `contents: read`). A job's `uses:` ref
must be a literal, so it cannot be `${{ vars.ACCEPTANCE_REF }}`. `gate.yml` is a
thin shim: the caller passes `acceptance_ref` as an input, the shim checks out
that ref and runs `bin/` from it, so behaviour is pinned by the ref whichever
shim version is called. A reusable workflow runs on its own runner, so an
artifact channel's caller uploads its tarball and passes the artifact name. The
verdict script fails on any `failed` or `error` row, on `mismatch` or
`inconsistent`, and on `unobserved` unless the caller passes `allow_unverified`.

### Convergent publishing

`ledger.json` and `LEDGER.md` are functions of the source files, so two
publishers always touch the same generated files and a rebase would conflict on
exactly those. The loop never rebases:

```
 repeat up to N:
   git fetch origin <ledger-branch>        (orphan-create if absent)
   git reset --hard origin/<ledger-branch>
   apply own change: write channels/<c>.json, merge-update deployed.json[<c>]
   regenerate ledger.json + LEDGER.md from all source files
   no difference?  done
   commit; git push (never --force)
     rejected -> repeat
```

A `concurrency` group per environment and channel reduces contention but does
not carry correctness: GitHub keeps one pending run per group and cancels an
older pending one even with `cancel-in-progress: false`.

### Ordering and forcing

Incoming channel versions are compared by semantic version (`Gem::Version`, after
stripping a leading `v`) with the version on file. Older is refused; equal or
newer replaces. The ledger's suite version is also monotonic: a publication under
an older suite version than `ledger.json` records is refused. `FORCE=true`
bypasses both and writes `run.forced` as the triggering actor. A non-semver
version is refused.

### Testing approach

Channel behaviour stays in Cucumber. The tooling here (composition root, run
record, ledger, publisher, validation) is tested with RSpec under `spec/`,
including publisher specs against a local bare git repository. This follows the
earlier change, where only the `greeting` scenarios were Cucumber scenarios.
Steps may only call the port, so literal Cucumber coverage of the publishing
scenarios would need a separate tooling suite with its own port.

## Risks / Trade-offs

- [Prod writes from CI] The record run greets on a deployed environment. The
  driver sends `X-Greeter-Synthetic: true`, but whether greeter-http isolates
  that traffic is unconfirmed → keep prod runs few (event-driven) and confirm
  isolation before enabling the prod record.
- [Dispatch token compromise] A stolen token can trigger runs → the payload
  carries no URL or repository; both come from committed config.
- [Markdown injection via version strings] → validate version patterns on
  `resolve` and again on `publish`, and escape every string in `LEDGER.md`.
- [Late or out-of-order runs] → semver guard on channel version and on suite
  version; `FORCE=true` for rollbacks.
- [`error` hides contract regressions] → accepted above; both fail the gate.
- [Gate unusable for http until headers exist] The gate fails closed on
  `unobserved` → callers use `allow_unverified` until greeter-http reports its
  version; the result is marked unverified.
- [Bootstrap] Nothing exists on the ledger branches at first → the first
  `workflow_dispatch` supplies the event's fields and creates the orphan branch.

## Migration Plan

1. Land the composition root, port, run record and schemas (specs go green).
2. Land the publisher and `bin/` scripts; exercise them against a local bare repo.
3. Add `record.yml` and `gate.yml`; add `branches-ignore: [ledger-prod,
   ledger-stage]` to `ci.yml`. Run `record.yml` manually for `stage` first, then
   `prod` once synthetic isolation is confirmed.
4. Tag `v0.2.0`.

Rollback: remove the workflows. The ledger branches are append-only history and
are safe to leave or delete. `bin/merge-ledger` remains as a local helper and now
emits `greeterhq.ledger.v2`.

## Open Questions

- The exact names of greeter-http's version headers. `HttpDriver` reads them from
  two constants, so this only affects that file. `X-Greeter-Version` and
  `X-Greeter-Core-Version` are assumed until greeter-http decides.
- Whether the invalid-name probe is side-effect free on greeter-http. It only
  affects the HTTP fallback in `build_info`; if it is not, drop the fallback and
  rely on passive observation.
