# Design

## Context

See proposal.md - Why. The repo is scaffolding only: `features/`,
`lib/greeter_acceptance/ports/`, and `lib/greeter_acceptance/drivers/` are
empty. This design establishes the port surface, the two first adapters, the
capability-gating mechanism, the scenario rollup rule, and the two trace
artifacts. Hard constraints from the project context: drivers are black-box
(process or URL only, never require another repo's code); step definitions never
mention exit codes, HTTP statuses, headers, or JSON; Ruby 3.3.5 with
`frozen_string_literal` and RuboCop clean; TDD with the failing test committed
first.

## Goals / Non-Goals

**Goals:**
- One port, two substitutable black-box adapters, exercised by one feature set.
- Capability differences are legible in a published ledger without any channel
  failing for lacking a capability.
- Channel idioms stay entirely inside drivers.

**Non-Goals:**
- No step-level `not_applicable`: gating and rollup are scenario-level only.
- No channel-specific outcomes in features (no 201/200/409/400/503, no exit
  codes). Those are asserted only in the driver-contract examples.
- No `WebDriver`/`MobileDriver`/`EventDriver`, no Pact wiring (Card 3).

## Decisions

### Neutral vocabulary limited to greeted / invalid-name

Features assert only two outcomes. Everything else (status codes, exit codes,
new-vs-repeat) is either a driver-contract detail or a capability-gated
observation. Alternative considered: a rich neutral vocabulary mapping every
HTTP status to a symbol (`:conflict`, `:unavailable`, `:malformed`). Rejected —
it smuggles HTTP semantics into a "neutral" vocabulary and the CLI cannot
produce most of them, so they are not shared behaviour.

### Port surface (GreeterDriver)

Introduced (no prior version — greenfield):

```ruby
# lib/greeter_acceptance/ports/greeter_driver.rb
channel                                  # => :cli | :http
capabilities                             # => Set[Symbol]  e.g. Set[:counting, :idempotency]
supports?(cap)                           # => Bool; cap in capabilities
greet(name, idempotency_key: nil)        # => GreetResult
count_for(name)                          # => Integer, or :not_applicable when counting unsupported
last_error                               # => neutral Symbol (:invalid_name, ...) or nil
last_native_error                        # => channel-native error detail (for debugging only)
native_idiom_for?(error)                 # => Bool; used by driver-contract examples

GreetResult = Struct.new(:message, :guest_name, :count, :outcome)
# outcome is :greeted for both new and repeat greetings; count carries the
# distinction on counting channels and is nil elsewhere.
```

How each driver implements the surface:

| Method | CliDriver (`greeter <name>`) | HttpDriver (POST /greetings) |
|---|---|---|
| `capabilities` | `Set[]` | `Set[:counting, :idempotency]` |
| `greet` | spawns process; exit 0 → `:greeted`, exit 2 → records `:invalid_name` | sends request (+ `Idempotency-Key` when given, `X-Greeter-Synthetic: true`); 201/200 → `:greeted`, 422 → `:invalid_name` |
| `count_for` | returns `:not_applicable` (no counting) | parses count from response body → Integer |
| `last_error` | maps exit 2 → `:invalid_name` | maps 422 → `:invalid_name` |

**D4 — `count_for` returns `:not_applicable` sentinel** rather than a Count
value object. Chosen for simplicity; the gating hook (below) means steps rarely
call `count_for` on a channel that cannot count anyway, so a value object would
be unused machinery.

### Scenario-per-behaviour (Way 1)

Each behaviour is its own single-purpose scenario. The universal greeting lives
in one scenario; the count observation lives in a separate `@capability-counting`
scenario. Alternative considered: one scenario mixing a universal greeting step
with a gated count step (per-step rollup). Rejected — it forces a per-step trace
schema and an action-vs-observation rollup rule. Way 1 keeps the rollup trivial:

> **Rollup rule:** any `not_applicable` step ⇒ the scenario is `not_applicable`.

This is safe only because scenarios are single-purpose, so it never wrongly
stamps a universal greeting as `not_applicable`. Ledger this produces:

```
requirement           cli              http      capability
--------------------  --------------   --------  --------------------
greeting-happy        passed           passed    --
greeting-invalid      passed           passed    --
greeting-count        not_applicable   passed    counting
greeting-returning    not_applicable   passed    counting
greeting-idempotent   not_applicable   passed    counting+idempotency
```

### Tag-driven gating via a Before hook (O2-c)

A single `Before` hook reads the scenario's `@capability-*` tags, compares them
to `driver.capabilities`, and marks the whole scenario `not_applicable` (skipping
its steps) when any required capability is missing. Alternatives considered:
per-step `supports?` guards (O2-a) and a sentinel-return check in each step
(O2-b) — both re-encode capability knowledge per step when the tag already says
it, and both are redundant once gating is scenario-level. The `@capability-*`
tag is the single source of capability truth, matching the project convention.

**Safety rail:** a startup check validates every `@capability-*` tag against the
known capability set, failing fast on a typo (e.g. `@capability-countng`) so it
cannot silently run on the CLI and fail.

### Trace artifacts (O3-a raw + O3-c derived)

Each run (`GREETER_CHANNEL` picks one channel) writes flat per-scenario rows to
`tmp/traceability.json` (`greeterhq.traceability.v1`), each `not_applicable` row
carrying `missing_capabilities`. A separate merge step reads the `cli` and `http`
files and derives `tmp/ledger.json`, the requirement-by-channel matrix. The merge
is separate because a single Cucumber run only ever sees one channel. Step-level
nesting (O3-b) was rejected: single-purpose scenarios make step detail redundant
and step text in a durable artifact ages badly.

## Risks / Trade-offs

- **Capability-tag typo runs on the wrong channel** → startup tag-validation
  check fails the run fast (the safety rail above).
- **`count_for` sentinel masks a genuine count bug on a counting channel** → the
  gating hook keeps `count_for` from being called on non-counting channels; on
  counting channels a missing/garbled count is a real failure, not
  `:not_applicable`, because HttpDriver returns an Integer or raises.
- **Ledger requires two runs** → the merge step lives in the "Verify and docs"
  task group, which already runs both channels; a single-channel run yields a
  partial ledger by design, not an error.
- **Semver mislabel** → proposal flags MINOR with a MAJOR caveat if any consumer
  is pinned to a pre-suite tag; verify `ACCEPTANCE_REF` pins before tagging.

## Open Questions

- Exact wire shape of `greeter-http`'s count field in the `201/200` response
  body. Deferrable: it affects only `HttpDriver#count_for` parsing, not the
  port, specs, or task breakdown. Resolve during apply against the real service
  (driver is black-box, so the response is observed, not assumed).
