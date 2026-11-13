# Proposal

## Why

The security review of `fix-candidate-ruby-version` found two gaps in how an
artifact channel's candidate is installed. Both are outside that change's scope.

- **S8:** `bundle install` evaluates the candidate's Gemfile, which is Ruby
  code. In the record workflow, a step that holds a token (`GH_TOKEN`, the
  job's read-only `github.token`) runs after that install. Candidate code can
  change `PATH` for later steps through `$GITHUB_PATH`, so it could plant a
  `gh` that reads the token.
- **S7:** `install` runs `bundle install` without frozen mode. A lockfile that
  is missing, or out of step with its Gemfile, is silently re-resolved, so the
  suite could test gems other than the ones the release pinned.

## What Changes

- In `record.yml`'s run job, the release-time lookup (the only step there that
  holds a token) moves before "Fetch the release". From then on, no step that
  holds a token runs after the candidate's code.
- `bin/cli-release install` runs `bundle install` in frozen mode
  (`BUNDLE_FROZEN=true`). A candidate without a `Gemfile.lock`, or with one that
  does not match its Gemfile, fails the install with a message saying so,
  before the suite runs.
- A new spec checks the token ordering in `record.yml` and `gate.yml`, so a
  later edit cannot reintroduce the gap.
- Suite version `0.3.0`.

## Non-goals

- Any change to greeter-cli, greeter-core or greeter-http. greeter-cli v0.1.2
  already ships a `Gemfile.lock` that pins greeter-core 0.1.3 from rubygems.org
  with a checksum.
- Isolating candidate code from `$GITHUB_ENV` / `$GITHUB_PATH` altogether. The
  run job exists to run that code. The goal is that nothing worth stealing
  remains after it has run.
- Job timeouts and showing Bundler's output during `bundle install`.
- The Ruby-version reader (`fix-candidate-ruby-version`).
- Any change to features, step definitions, the port, or the drivers.

## Channels affected

- **cli**: its record runs fetch the release time before the release is
  downloaded. Its gate and record installs must match its lockfile exactly.
- **http**: unaffected. It has no install step and no token step.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `acceptance-gate`: adds that an artifact channel's candidate is installed
  exactly as its lockfile pins, and that no step that holds a token runs after
  candidate code.
- `ledger-publication`: adds the same two guarantees for record runs.

## Impact

- **Code**:
  - `bin/cli-release` (`install` and its environment);
  - `.github/workflows/record.yml` (one step moves; no other edit);
  - `gate.yml` is unchanged, since it has no token step, but the new spec covers
    it.
- **Tests**:
  - new examples for `install` in `spec/cli_release_spec.rb`, the file
    `fix-candidate-ruby-version` creates;
  - a new `spec/workflow_token_order_spec.rb`.

  Both capabilities are tooling capabilities, so their scenarios are verified by
  RSpec (`.kiro/steering/scenario-traceability.md`).
- **Docs**: the README's gate and record sections: a lockfile is required.
- **Semver**: minor, `v0.3.0`. A candidate without a matching lockfile used to be
  installed and now fails, which is stricter. greeter-cli v0.1.2 ships a
  lockfile, so it is expected to keep passing; task 4.3 checks this.
- **When it takes effect**:
  - The `record.yml` reorder takes effect as soon as it is merged to `main`:
    GitHub runs the workflow file from the default branch, not from the suite
    tag.
  - The frozen install takes effect in record mode once `v0.3.0` is tagged,
    because the run job runs the tag's `bin/`.
- **Consumers**:
  - greeter-cli must bump `ACCEPTANCE_REF` to `v0.3.0` for its gate to install
    frozen.
  - greeter-http need not bump.
- **Order**: lands after `fix-candidate-ruby-version` (`v0.2.2`). Both edit
  `bin/cli-release` and `spec/cli_release_spec.rb`.
