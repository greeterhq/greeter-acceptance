# Traceability, deployed and ledger schemas

greeter-acceptance writes three kinds of JSON document:

- a per-channel **traceability** file for each run (`greeterhq.traceability.v2`);
- a **deployed record** of what is deployed in an environment
  (`greeterhq.deployed.v1`);
- a cross-channel **ledger** derived from the two (`greeterhq.ledger.v2`).

Together they answer "which channel honours which requirement, which version was
tested, and where do capabilities differ?"

## `greeterhq.traceability.v2` (per channel)

Written by every run to `tmp/traceability.json`. It says what was tested (suite
version, channel version, core version, environment), when and by which run, and
whether the channel's own reported version could be verified.

```json
{
  "schema": "greeterhq.traceability.v2",
  "run": {
    "channel": "cli",
    "environment": "local",
    "suite_version": "v0.1.0",
    "channel_version": "v0.1.2",
    "channel_sha": null,
    "core_version": "0.1.3",
    "verification": "verified",
    "recorded_at": "2026-11-08T05:47:20Z",
    "run_id": "42",
    "released_at": null,
    "forced": null
  },
  "results": [
    {
      "requirement": "greeting-happy",
      "scenario": "greet-new-guest",
      "status": "passed"
    },
    {
      "requirement": "greeting-count",
      "scenario": "count-new-guest",
      "status": "not_applicable",
      "missing_capabilities": ["counting"]
    }
  ]
}
```

Fields:

- `schema` — always `greeterhq.traceability.v2`.
- `run.channel` — the channel under test (`cli`, `http`, ...).
- `run.environment` — the environment the run targeted (`prod`, `stage`, or
  `local` when none is given).
- `run.suite_version` — the suite version that produced the results (`v` plus
  `GreeterAcceptance::VERSION`).
- `run.channel_version` — the version the results are attributed to, with a
  leading `v`. This is what the channel reported when that was unambiguous. With
  nothing observed it is the expected version (a claim, see `verification`). With
  two different versions observed it is `null`.
- `run.channel_sha` — the commit the run was told to expect, or `null`.
- `run.core_version` — the greeter-core version the channel reported, or `null`.
- `run.verification` — how far `channel_version` can be trusted:
  - `verified` — every observation equals the expected version.
  - `mismatch` — the observed version differs from the expected version. The
    results are attributed to the observed version, never the expected one.
  - `inconsistent` — two different versions were observed during the run, so the
    results cannot be attributed to one version.
  - `unobserved` — the channel reported no version, or there was no expected
    version to compare with.
- `run.recorded_at` — UTC ISO 8601 time the record was written (runner clock).
- `run.run_id` — the CI run identifier, or `null` outside CI.
- `run.released_at` — the release time of an artifact channel, or `null`.
- `run.forced` — the actor who forced the publication, or `null`.
- `results[]` — one row per scenario:
  - `requirement` — slug from the scenario's `@requirement-<slug>` tag.
  - `scenario` — slug from the scenario's `@scenario-<slug>` tag.
  - `status` — `passed`, `failed`, `error`, or `not_applicable`.
  - `missing_capabilities` — present only on `not_applicable` rows; the
    capabilities the channel lacked that gated the scenario.

`error` means the channel itself could not be reached or returned something the
driver did not recognise while the scenario ran. It wins over `failed`: a
scenario that hit an infrastructure error is `error` even if an assertion also
failed.

**Rollup rule:** any `not_applicable` step makes the whole scenario
`not_applicable`. This is safe because scenarios are single-purpose: a scenario
is either entirely universal or entirely capability-gated.

### What feeds the run context

| Variable | Becomes | Default |
| --- | --- | --- |
| `GREETER_CHANNEL` | `run.channel` | (required) |
| `GREETER_ENVIRONMENT` | `run.environment` | `local` |
| `GREETER_EXPECTED_VERSION` | the version `run.verification` compares against | none |
| `GREETER_EXPECTED_SHA` | `run.channel_sha` | none |
| `GITHUB_RUN_ID`, or `GREETER_RUN_ID` | `run.run_id` | none |
| `GREETER_RELEASED_AT` | `run.released_at` | none |

## `greeterhq.deployed.v1` (per environment)

Which version and commit of each channel is deployed in one environment. It is
updated whenever a channel is released, whatever its tests then say, so it stays
true when a run fails or errors. The ledger compares it with each channel's
result to tell a current result from a stale one.

```json
{
  "schema": "greeterhq.deployed.v1",
  "environment": "prod",
  "channels": {
    "cli": { "version": "v0.1.2", "sha": "abc1234", "artifact": "tag", "run_id": "812" },
    "http": { "version": "v1.2.3", "sha": "def4567", "run_id": "815" }
  }
}
```

Each channel entry has `version` and `sha`, plus `artifact` (artifact channels
only) and `run_id`, which are left out when they have no value.

## `greeterhq.ledger.v2` (derived, cross-channel)

The requirement-by-channel matrix: the published view of the capability
frontier. It is a pure function of the channel results, the deployed record and
the suite version. It carries no timestamp of its own, and every collection is
sorted, so regenerating it from the same inputs gives identical output.

```json
{
  "schema": "greeterhq.ledger.v2",
  "environment": "prod",
  "suite": { "version": "v0.2.0" },
  "channels": {
    "cli": {
      "state": "current",
      "reasons": [],
      "channel_version": "v0.1.2",
      "core_version": "0.1.3",
      "suite_version": "v0.2.0",
      "verification": "verified",
      "recorded_at": "2026-11-08T05:47:20Z",
      "run_id": "812"
    },
    "http": { "state": "missing", "reasons": [] }
  },
  "requirements": {
    "greeting-count": { "cli": "not_applicable", "http": "missing" },
    "greeting-happy": { "cli": "passed", "http": "missing" }
  }
}
```

A **cell** (requirement by channel) is one of:

- `passed`, `failed`, `error` — from the channel's result;
- `not_applicable` — the channel lacks a capability the scenario needs;
- `missing` — there is no row. This is never reported as `not_applicable`, which
  is reserved for a declared capability gap.

A **column** (channel) has a `state`:

- `current` — the result was produced by the ledger's suite version for the
  channel version now deployed.
- `stale` — the result exists but is out of date. `reasons` says why: `suite`
  (produced by an older suite version) and/or `channel` (a newer version is
  deployed than the result covers). Stale columns keep their last known cell
  statuses; the rendering marks them as stale.
- `missing` — the channel has no result. Every cell in the column is `missing`.

A column also carries `channel_version`, `core_version`, `suite_version`,
`verification`, `recorded_at` and `run_id` from the channel's result.
`verification` is shown beside the state but does not change it.

The requirement list is read from the `@requirement-<slug>` tags in `features/`,
and the channel list is `CompositionRoot.channels`.

`LEDGER.md` renders the same data for people: a table of channels (state,
versions, verification, when and by which run) and a requirement-by-channel table.
Values from a channel's result are written as character references where they
could form markup.

### Building a ledger locally

`bin/merge-ledger` builds `ledger.json` and `LEDGER.md` from a directory of
channel results, with no git involved. Keep each run's file under its channel's
name first:

```bash
mkdir -p tmp/channels
cp tmp/traceability.json tmp/channels/cli.json    # after the cli run
cp tmp/traceability.json tmp/channels/http.json   # after the http run
bin/merge-ledger --channels tmp/channels --deployed tmp/deployed.json \
  --environment prod --suite-version v0.2.0 --out tmp/ledger
```

`--deployed` is optional (the default is an empty record); `--features` defaults
to `features`.
