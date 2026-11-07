# Tasks

Notes for whoever applies this change:

- Group 1 writes files under `spec/`. Apply never edits `spec/` or `features/`,
  so write group 1 as its own step before `/opsx-apply`, as was done for
  `add-neutral-acceptance-suite`. Commit the red tests before group 2.
- Tasks 3.3 and 4.2 edit `features/support/` wiring (`env.rb`, `hooks.rb`). These
  are implementation, not scenarios or steps, but the test-edit guard hook blocks
  them. Allow them with `tmp/allow-test-edits`, and do not touch any `.feature`
  file or step definition.
- Run everything under Ruby 3.3.13 (`.ruby-version`).

## 1. Red tests

- [ ] 1.1 Write `spec/composition_root_spec.rb`: `build_driver(env:)` returns the
  cli driver for `cli`, the http driver for `http`, and refuses an unset or
  unknown `GREETER_CHANNEL` and a missing `GREETER_BASE_URL` with a clear
  message; `build_observed_driver` wraps the driver; `channels` is `cli`, `http`.
  Verify it fails with `NameError` for `CompositionRoot`, not a syntax error.
- [ ] 1.2 Extend the driver contract (`spec/drivers/greeter_driver_contract.rb`)
  and the cli and http driver specs: the port surface includes `build_info`;
  `build_info` returns a value with channel and core versions or nil and changes
  no count; a driver pointed at an unreachable channel (nonexistent command,
  `http://127.0.0.1:1`) returns the `infrastructure_error` outcome and does not
  raise. Verify the new examples fail on the missing `build_info` and on the
  raised error, and that the existing examples are unchanged.
- [ ] 1.3 Write `spec/observed_driver_spec.rb`: the decorator forwards every port
  method, records an infrastructure error even when a later greet succeeds, and
  collects `build_info`. Verify it fails with `NameError`.
- [ ] 1.4 Write `spec/run_record_spec.rb`: scenario status maps to passed, failed
  or error (an observed infrastructure error wins over a failed assertion); a
  gated scenario is not applicable; verification is verified, mismatch,
  inconsistent or unobserved; the trace v2 document carries the run context
  (suite version, channel version and sha, core version, environment, recording
  time, run id). Verify it fails with `NameError`.
- [ ] 1.5 Write `spec/ledger_spec.rb` for `greeterhq.ledger.v2`: cell statuses
  including `error` and `missing`; a requirement with no row is missing, not not
  applicable; a known channel with no file has every cell missing; column state
  is current, stale for an older suite, stale for a moved-on deployed version, or
  missing; the requirement list comes from `@requirement-*` tags; output is
  identical across runs and input orders. Verify it fails with `NameError`.
- [ ] 1.6 Write `spec/ledger_renderer_spec.rb` for `LEDGER.md`: a context header
  per column, stale columns marked, missing shown, markup in versions rendered as
  plain text, deterministic output. Verify it fails with `NameError`.
- [ ] 1.7 Write `spec/deployed_spec.rb` for `greeterhq.deployed.v1`: a keyed
  update changes only that channel's entry, and the update happens whatever the
  result status was. Verify it fails with `NameError`.
- [ ] 1.8 Write `spec/environments_spec.rb` and `spec/event_validation_spec.rb`:
  targets resolve from the committed config; a supplied address is refused; the
  host must match the environment's pattern; unknown environments and channels
  are named and refused; an event with an unknown channel or environment, or a
  malformed version or sha, is refused. Verify both fail with `NameError`.
- [ ] 1.9 Write `spec/resolver_spec.rb`: a channel-released event yields a matrix
  of one channel; a new suite tag yields every channel named in `deployed.json`;
  a manual run takes the event's fields and a rerun-all option; the latest
  published suite tag is chosen, not the default branch head. Verify it fails
  with `NameError`.
- [ ] 1.10 Write `spec/publisher_spec.rb` against a local bare git repository:
  publishing writes only the channel's own file and its deployed entry, then
  regenerates the generated views; two publishers for different channels
  converge to a ledger containing both; a rejected push is retried by
  re-reading, re-applying and regenerating, never rebasing; no difference means
  no commit; the first publish creates the branch. Verify it fails with
  `NameError`.
- [ ] 1.11 Write `spec/publisher_guards_spec.rb`: an older channel version is
  refused and an equal or newer one replaces; an older suite version cannot
  lower the ledger's suite version; force overrides both and records the actor;
  a non-semver version is refused; unknown result fields are dropped; a result
  naming another channel is refused; oversized input is refused. Verify it fails
  with `NameError`.
- [ ] 1.12 Write `spec/gate_verdict_spec.rb`: failed or error rows fail the gate;
  mismatch and inconsistent fail it; unobserved fails unless unverified is
  allowed, which marks the result unverified; not applicable never fails; a
  missing acceptance reference fails. Verify it fails with `NameError`.
- [ ] 1.13 Run `bundle exec rspec` and confirm every new example fails for the
  right reason (`NameError`, `NoMethodError` or an expectation), none on syntax.
  Commit the red tests before group 2.

## 2. Port and drivers

- [ ] 2.1 Add `BuildInfo` and the abstract `build_info` to the port module, and
  document the `infrastructure_error` outcome and last error. Verify the port
  surface examples for `build_info` in 1.2 pass.
- [ ] 2.2 Update `CliDriver`: `build_info` runs `<command> --version`, parses
  `greeter-cli <v> (greeter-core <v>)`, caches it, and returns nil when it
  cannot parse; a spawn failure or any exit other than 0 and 2 returns the
  `infrastructure_error` outcome instead of raising. Verify
  `rspec spec/drivers/cli_driver_spec.rb` passes with the downloaded greeter-cli
  release, and the unreachable example passes with a nonexistent command.
- [ ] 2.3 Update `HttpDriver`: read the version headers (two constants) off each
  response; with none seen, probe with an invalid-name greet; connection, DNS,
  TLS and timeout errors and any status other than 200, 201 and 422 return the
  `infrastructure_error` outcome instead of raising. Verify
  `rspec spec/drivers/http_driver_spec.rb` passes against a local stub server
  that sends version headers, passes the unreachable example, and returns nil
  build info against the live endpoint until greeter-http reports versions.
- [ ] 2.4 Document `build_info` and `infrastructure_error` in the README "Adding
  a channel" steps. Verify the README names both and RuboCop is clean.

## 3. Composition root and observation

- [ ] 3.1 Create `lib/greeter_acceptance/composition_root.rb` with
  `build_driver(env:)` and `channels`. Verify the `build_driver` and `channels`
  examples in `spec/composition_root_spec.rb` pass.
- [ ] 3.2 Add the `Observed` decorator and `build_observed_driver`. Verify
  `spec/observed_driver_spec.rb` and the remaining composition root examples
  pass.
- [ ] 3.3 Reduce `features/support/env.rb` to a World module that calls
  `build_observed_driver`, and update its header comment. Verify
  `bundle exec cucumber --dry-run` loads all five scenarios and a run with
  `GREETER_CHANNEL=cli` against the real greeter-cli still passes its two
  universal scenarios.
- [ ] 3.4 Amend the composition-root rule in `openspec/config.yaml`, `README.md`
  (Architecture and Configuration) and `.kiro/steering/architecture.md` to say
  `composition_root.rb` is the only place a driver is constructed. Verify a grep
  finds no remaining text saying `env.rb` is the only composition root, and
  `openspec validate --all --strict` passes.

## 4. Run record, hooks and trace v2

- [ ] 4.1 Add `lib/greeter_acceptance/version.rb` (`VERSION`) and `RunRecord`,
  replacing `Trace`: rows, status mapping, observations, verification states, the
  run context, and the `greeterhq.traceability.v2` writer. Verify
  `spec/run_record_spec.rb` passes and no reference to `Trace` remains.
- [ ] 4.2 Rewrite `features/support/hooks.rb` to use `BeforeAll`, `After` and
  `AfterAll` with `RunRecord`, keeping capability gating and the unknown-tag
  check, and removing `$greeter_trace` and `at_exit`. Read the environment,
  expected version, run id and sha from `GREETER_*` and `GITHUB_RUN_ID`. Verify a
  cli run against the real greeter-cli writes a v2 `tmp/traceability.json` with
  the run context, and a run with `GREETER_CLI_CMD` pointing at a missing
  command records `error` rows.
- [ ] 4.3 Update `docs/traceability-schema.md` for trace v2 (the `error` status,
  the run context, verification). Verify the documented example has exactly the
  keys of a real `tmp/traceability.json`.

## 5. Targets, events and resolution

- [ ] 5.1 Create `config/environments.yml` for `prod` and `stage` with the
  ledger branch, each http `base_url` and `host_pattern`, and the cli release
  repository, with a comment explaining each key. Ask the maintainers for the
  real URLs and patterns; do not guess them. Verify the file parses and every
  `base_url` matches its own `host_pattern`.
- [ ] 5.2 Implement `lib/greeter_acceptance/environments.rb`. Verify
  `spec/environments_spec.rb` passes.
- [ ] 5.3 Implement event validation and `bin/resolve`, which builds the matrix
  from an event, a new suite tag, or a manual run, and picks the latest
  published suite tag. Verify `spec/event_validation_spec.rb` and
  `spec/resolver_spec.rb` pass, and `bin/resolve` prints a matrix for a sample
  event.

## 6. Ledger v2, deployed record and rendering

- [ ] 6.1 Implement `lib/greeter_acceptance/deployed.rb`. Verify
  `spec/deployed_spec.rb` passes.
- [ ] 6.2 Replace `Ledger` with the v2 generator: cells, column states and
  reasons, the requirement list from `features/`, deterministic output. Verify
  `spec/ledger_spec.rb` passes.
- [ ] 6.3 Implement the `LEDGER.md` renderer with escaping. Verify
  `spec/ledger_renderer_spec.rb` passes.
- [ ] 6.4 Update `bin/merge-ledger` to build `ledger.json` and `LEDGER.md` from a
  directory of channel files and an optional `deployed.json`. Verify it produces
  the matrix from two real traces and is identical on a second run.
- [ ] 6.5 Document `greeterhq.deployed.v1` and `greeterhq.ledger.v2` in
  `docs/traceability-schema.md`. Verify the documented examples match the
  generator's output for fixtures.

## 7. Publisher

- [ ] 7.1 Implement `lib/greeter_acceptance/publisher.rb`: apply the channel's
  own change, regenerate the views, commit only when something differs, and
  create the orphan branch on first publish. Verify the first, regeneration and
  no-change examples in `spec/publisher_spec.rb` pass.
- [ ] 7.2 Add the retry loop: fetch, reset to the remote, re-apply, regenerate,
  push without force, repeat up to a limit. Verify the convergence and
  rejected-push examples pass against the local bare repository.
- [ ] 7.3 Add the guards: semver ordering of channel versions, a monotonic suite
  version, `force` with the actor recorded, and refusal of non-semver versions.
  Verify the ordering and force examples in `spec/publisher_guards_spec.rb`
  pass.
- [ ] 7.4 Add untrusted-data handling: a field allowlist, channel match, a size
  cap, version patterns, and escaping. Verify the remaining guards examples
  pass.
- [ ] 7.5 Add `bin/publish` using only the standard library. Verify
  `ruby --disable-gems bin/publish --help` runs with no gems loaded.
- [ ] 7.6 Write `docs/ledger-publication.md` covering the branch layout, the
  guards and forcing. Verify each described file name and field exists in a
  publisher test run.

## 8. Gate, record workflow and CI

- [ ] 8.1 Add `bin/probe`, which builds a driver through the composition root and
  prints the build info and whether the probe hit an infrastructure error.
  Verify it against the real greeter-cli and the live http endpoint.
- [ ] 8.2 Add `bin/gate-verdict`. Verify `spec/gate_verdict_spec.rb` passes.
- [ ] 8.3 Add `.github/workflows/gate.yml` (`workflow_call`, `contents: read`)
  that checks out the supplied `acceptance_ref`, takes the artifact by name,
  probes, runs Cucumber, and runs the verdict. Verify the YAML parses, the
  permissions block is read-only, and `actionlint` passes if it is installed.
- [ ] 8.4 Add `.github/workflows/record.yml` with the three stages: `resolve`,
  `run` (`contents: read`, `persist-credentials: false`, checksum and tag-to-sha
  checks, no token in the environment of the step that executes downloaded code)
  and `publish` (`contents: write`, no gems, `!cancelled()`, a concurrency group
  per environment and channel), plus a check that `VERSION` equals the tag.
  Verify the YAML parses, only `publish` has write permission, and `actionlint`
  passes if it is installed.
- [ ] 8.5 Change `ci.yml` to ignore the `ledger-prod` and `ledger-stage` branches
  (`branches-ignore`). Verify the YAML parses and `lint` and `spec-gate` are
  unchanged.
- [ ] 8.6 Document the gate and record modes in the README: how a channel repo
  calls the gate (a `uses:` snippet and its inputs), the `channel-released`
  payload, manual runs, `rerun_all` and `force`, and the ledger branches. Verify
  every YAML snippet in the README parses.

## 9. Verify and docs

- [ ] 9.1 Run `bundle exec rspec` for the tooling specs, and the driver contract
  with `GREETER_CHANNEL=cli` and a real greeter-cli, then with
  `GREETER_CHANNEL=http`. Verify everything passes.
- [ ] 9.2 Run `GREETER_CHANNEL=cli bundle exec cucumber` and
  `GREETER_CHANNEL=http bundle exec cucumber`, and check each
  `tmp/traceability.json` against `docs/traceability-schema.md`. Verify the
  universal scenarios pass on both and the capability scenarios record not
  applicable on cli.
- [ ] 9.3 Publish both channels' results with `bin/publish` to a local bare
  repository, then regenerate. Verify `ledger.json` and `LEDGER.md` match the
  design's shapes and are identical on a second regeneration.
- [ ] 9.4 Confirm `features/greeting.feature` and the step definitions are
  unchanged. Verify `git diff main -- features/greeting.feature
  features/step_definitions` is empty.
- [ ] 9.5 Run RuboCop, check `frozen_string_literal` on every Ruby file, and run
  `openspec validate publish-channel-ledger --strict` and
  `openspec validate --all --strict`. Verify all pass.

## Workflow follow-up

- Set `GreeterAcceptance::VERSION` and tag `v0.2.0` once the change is accepted.
- Archive the change after review.
- Outside this repo, and not tracked here: greeter-http reports its version on
  every response; greeter-cli and greeter-http send `channel-released` and call
  the gate from their release jobs; the http release flow deploys to stage before
  the gate; greeter-docs adds a `docs-refresh` listener.
