# Tasks

Notes for whoever applies this change:
- Apply after `fix-candidate-ruby-version` is merged. Its new
  `spec/cli_release_spec.rb` and its `bin/cli-release` changes are the starting
  point.
- Only these files change:
  - `bin/cli-release` (`install`, `CLEAN_ENV`);
  - `.github/workflows/record.yml` (one step moves);
  - `spec/cli_release_spec.rb` (new examples only);
  - the new `spec/workflow_token_order_spec.rb`;
  - `lib/greeter_acceptance/version.rb`;
  - the README.
- `features/`, the step definitions and `gate.yml` stay untouched. The port and
  the drivers are unchanged, so there are no feature, step definition or
  driver-contract examples.

## 1. Red tests

- [ ] 1.1 Add `install` examples to `spec/cli_release_spec.rb`. Each uses a
  tmpdir holding a Gemfile with `source 'https://rubygems.org'` and no gems,
  so no network is needed.
  - No `Gemfile.lock`: raises `CliRelease::Failure` with a message saying the
    lockfile must be present and match the Gemfile.
  - A lockfile made by `bundle lock`, then `gem 'json'` added to the Gemfile:
    raises the same failure.
  - A matching lockfile: writes an executable launcher.

  Verify red for the right reason: the first two examples report that no error
  was raised, because today's install re-resolves.
- [ ] 1.2 Write `spec/workflow_token_order_spec.rb`, per the design's
  "ordering spec":
  - for `record.yml` and `gate.yml`, no step after the first
    `bin/cli-release install` step references `secrets.`, `github.token` or
    `steps.<id>.outputs.token` in `env:`, `with:` or `run:`;
  - offending steps are named;
  - in `record.yml`, "Look up when the release was published" comes before
    "Fetch the release (checksum and tag checked)".

  Verify red for the right reason: the `record.yml` examples fail naming "Look
  up when the release was published", and the `gate.yml` example passes.
- [ ] 1.3 Run RuboCop on both spec files. Verify no offenses and a
  `frozen_string_literal` magic comment.

## 2. Frozen install and step order

- [ ] 2.1 Add `'BUNDLE_FROZEN' => 'true'` to `CliRelease::CLEAN_ENV`, and add the
  reason to `install`'s failure message. Verify the 1.1 examples pass and
  RuboCop is clean.
- [ ] 2.2 In `record.yml`'s run job, move "Look up when the release was
  published" to just before "Fetch the release (checksum and tag checked)",
  with its `if`, `continue-on-error`, `env` and outputs unchanged. Update its
  comment to say why it runs first. Verify:
  - the 1.2 examples pass;
  - `actionlint .github/workflows/record.yml` reports nothing new (the known
    `client-id` false alarm and the SC2155 warning in the publish step stay);
  - `git diff` shows only the move and the comment.

## 3. Version and docs

- [ ] 3.1 Set `GreeterAcceptance::VERSION` to `'0.3.0'`. Verify `ruby -Ilib
  -rgreeter_acceptance/version -e 'puts GreeterAcceptance::VERSION'` prints
  `0.3.0`.
- [ ] 3.2 In the README's gate and record sections, say that an artifact
  channel must ship a `Gemfile.lock` that matches its Gemfile and is installed
  frozen, and what a refusal looks like. Verify every YAML snippet in the
  README still parses.

## 4. Verify and docs

- [ ] 4.1 Run the tooling specs with `bundle exec rspec`, and the driver contract
  with `GREETER_CHANNEL=cli` (real greeter-cli launcher) and `GREETER_CHANNEL=http`
  (stage endpoint). Verify everything passes.
- [ ] 4.2 Run `GREETER_CHANNEL=cli bundle exec cucumber` and
  `GREETER_CHANNEL=http bundle exec cucumber`. Check each `tmp/traceability.json`
  against `docs/traceability-schema.md`. Verify the results match the previous
  release.
- [ ] 4.3 Run `bin/cli-release fetch` greeter-cli v0.1.2, then
  `bin/cli-release install` on it, under Ruby 3.3.5. Verify the frozen install
  succeeds and the launcher prints `greeter-cli 0.1.2 (greeter-core 0.1.3)`,
  which shows the shipped lockfile matches.
- [ ] 4.4 Confirm the files that must not change are unchanged. Verify
  `git diff main -- features .github/workflows/gate.yml` is empty.
- [ ] 4.5 Run RuboCop, check `frozen_string_literal` on every Ruby file, and run
  `openspec validate harden-candidate-install --strict` and
  `openspec validate --all --strict`. Verify all pass.

## Workflow follow-up

- Merge to `main`. The `record.yml` reorder is live from then on. Tag `v0.3.0`
  for the frozen install.
- Outside this repo: greeter-cli bumps `ACCEPTANCE_REF` to `v0.3.0`.
- Archive the change after review.
