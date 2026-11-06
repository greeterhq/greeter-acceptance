# Tasks

## 1. Red tests

- [x] 1.1 Write the five neutral feature scenarios (greeting-happy,
  greeting-invalid, greeting-count, greeting-returning, greeting-idempotent) in
  `features/`, each tagged `@requirement-<slug>` and `@scenario-<slug>`, with the
  count/returning/idempotent scenarios additionally tagged `@capability-counting`
  (and idempotent also `@capability-idempotency`). Verify `cucumber --dry-run`
  lists all five scenarios with undefined steps.
- [x] 1.2 Write step definitions in `features/step_definitions/` that call only
  the `GreeterDriver` port (no exit codes, statuses, headers, or JSON). Verify
  `bundle exec cucumber` fails red because the driver/port is undefined
  (NameError), not a syntax error.
- [x] 1.3 Write `spec/drivers/greeter_driver_contract.rb` as a shared RSpec
  example group asserting the port surface, honest capability declaration,
  neutral greeted/invalid-name mapping, and the `:not_applicable` count sentinel.
  Verify `bundle exec rspec spec/drivers` fails red because no driver yet
  satisfies the contract.

## 2. Port and composition root

- [x] 2.1 Define `lib/greeter_acceptance/ports/greeter_driver.rb` with the port
  surface (channel, capabilities, supports?, greet, count_for, last_error,
  last_native_error, native_idiom_for?) and the `GreetResult` struct. Verify the
  contract example's port-surface check no longer errors on missing methods.
- [x] 2.2 Write `features/support/env.rb` as the only composition root, selecting
  the driver from `GREETER_CHANNEL` (cli|http) and reading `GREETER_CLI_DIR`,
  `GREETER_CLI_CMD`, `GREETER_BASE_URL`. Verify an unset/invalid `GREETER_CHANNEL`
  fails fast with a clear message.

## 3. CLI driver

- [x] 3.1 Implement `lib/greeter_acceptance/drivers/cli_driver.rb` as a black-box
  adapter spawning `greeter <name>` (exit 0 → `:greeted`, exit 2 →
  `:invalid_name`), declaring `capabilities == Set[]` and returning
  `:not_applicable` from `count_for`. Verify the contract examples pass with
  `GREETER_CHANNEL=cli bundle exec rspec spec/drivers`.

## 4. HTTP driver

- [x] 4.1 Implement `lib/greeter_acceptance/drivers/http_driver.rb` as a black-box
  adapter POSTing to `/greetings` over Net::HTTP, sending `Idempotency-Key` when
  given and `X-Greeter-Synthetic: true` by default, declaring
  `capabilities == Set[:counting, :idempotency]`, mapping 201/200 → `:greeted`
  and 422 → `:invalid_name`, and parsing the count from the response body. Verify
  the contract examples pass with `GREETER_CHANNEL=http bundle exec rspec
  spec/drivers`.

## 5. Capability gating and rollup

- [x] 5.1 Add the `Before` hook in `features/support/` that marks a scenario
  `not_applicable` (skipping its steps) when any `@capability-*` tag names a
  capability the active driver lacks. Verify the counting/idempotency scenarios
  run on http and record not_applicable on cli.
- [x] 5.2 Add the startup tag-validation check that fails fast when a
  `@capability-*` tag names an unknown capability. Verify introducing a bogus tag
  (e.g. `@capability-countng`) aborts the run and names the tag; remove the bogus
  tag after.

## 6. Traceability and ledger

- [x] 6.1 Implement the per-channel trace writer emitting
  `tmp/traceability.json` (`greeterhq.traceability.v1`) with one row per scenario
  (passed/failed/not_applicable) and `missing_capabilities` on not_applicable
  rows. Document the schema in `docs/traceability-schema.md`. Verify a cli run and
  an http run each produce a well-formed file matching the documented schema.
- [x] 6.2 Implement the merge step deriving `tmp/ledger.json` (the
  requirement-by-channel matrix) from the cli and http trace files, and document
  it. Verify the merged ledger shows greeting-count/returning/idempotent as
  not_applicable for cli and passed for http.

## 7. Verify and docs

- [x] 7.1 Run the full suite on both channels (`GREETER_CHANNEL=cli bundle exec
  cucumber` and `GREETER_CHANNEL=http bundle exec cucumber`) and verify the
  universal scenarios pass on both while capability scenarios pass on http and
  record not_applicable on cli.
- [x] 7.2 Validate `tmp/traceability.json` from each run against
  `docs/traceability-schema.md`, confirm `tmp/ledger.json` matches the design's
  ledger table, and verify RuboCop is clean and every file carries
  `frozen_string_literal`.
- [x] 7.3 Run `openspec validate add-neutral-acceptance-suite --strict` and verify
  it passes.
