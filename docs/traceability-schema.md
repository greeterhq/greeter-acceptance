# Traceability and ledger schemas

greeter-acceptance writes two JSON artifacts per CI cycle: a per-channel
**traceability** file for each run, and a derived cross-channel **ledger** merged
from them. Together they answer "which channel honours which requirement, and
where do capabilities differ?"

## `greeterhq.traceability.v1` (per channel)

Written by every run to `tmp/traceability.json`, plus a channel-tagged copy
`tmp/traceability-<channel>.json` (e.g. `tmp/traceability-cli.json`) so both
channels' files coexist for the merge step.

```json
{
  "schema": "greeterhq.traceability.v1",
  "run": {
    "channel": "cli",
    "at": "2026-10-31T10:00:00Z",
    "acceptance_ref": "v0.3.0"
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

- `schema` — always `greeterhq.traceability.v1`.
- `run.channel` — the channel under test for this run (`cli`, `http`, ...).
- `run.at` — UTC ISO 8601 timestamp of the run.
- `run.acceptance_ref` — the suite tag consumers pin (`ACCEPTANCE_REF`), or
  `null` when unset.
- `results[]` — one row per scenario:
  - `requirement` — slug from the scenario's `@requirement-<slug>` tag.
  - `scenario` — slug from the scenario's `@scenario-<slug>` tag.
  - `status` — `passed`, `failed`, or `not_applicable`.
  - `missing_capabilities` — present only on `not_applicable` rows; the
    capabilities the channel lacked that gated the scenario.

**Rollup rule:** any `not_applicable` step makes the whole scenario
`not_applicable`. This is safe because scenarios are single-purpose: a scenario
is either entirely universal or entirely capability-gated.

## `greeterhq.ledger.v1` (derived, cross-channel)

Produced by `bin/merge-ledger` to `tmp/ledger.json`, merging the per-channel
traceability files into a requirement-by-channel matrix. This is the published
view of the capability frontier.

```json
{
  "schema": "greeterhq.ledger.v1",
  "channels": ["cli", "http"],
  "requirements": {
    "greeting-happy":      { "cli": "passed",         "http": "passed" },
    "greeting-invalid":    { "cli": "passed",         "http": "passed" },
    "greeting-count":      { "cli": "not_applicable",  "http": "passed" },
    "greeting-returning":  { "cli": "not_applicable",  "http": "passed" },
    "greeting-idempotent": { "cli": "not_applicable",  "http": "passed" }
  }
}
```

Fields:

- `schema` — always `greeterhq.ledger.v1`.
- `channels` — the channels merged, in input order.
- `requirements` — map of requirement slug to a per-channel status map.

Generate it after both channel runs:

```bash
bin/merge-ledger tmp/traceability-cli.json tmp/traceability-http.json
```
