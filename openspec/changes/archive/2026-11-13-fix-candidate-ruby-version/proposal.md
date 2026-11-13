# Proposal

## Why

The gate and the record workflow read the `ruby` line of an artifact channel's
Gemfile and pass its text straight to `ruby/setup-ruby`. greeter-cli's Gemfile
now says `ruby '~> 3.3.5'`, which is a Bundler requirement, not a version, so
setup-ruby fails with "Unknown engine ~> 3.3.5" and no cli candidate or release
can be gated or recorded.

## What Changes

- `bin/cli-release ruby-version` translates the Gemfile's `ruby` requirement
  into a version setup-ruby accepts and that satisfies the requirement:
  - an exact `X.Y.Z` (or `= X.Y.Z`) becomes `X.Y.Z`;
  - `~>` or `>=` with `X.Y.Z` or `X.Y` becomes the series `X.Y`, whose newest
    patch setup-ruby installs.
- Anything it cannot translate to one safe version fails closed, naming the
  line, before the candidate is installed. This covers:
  - a bare `X.Y` or `= X.Y` (Bundler reads it as exactly `X.Y.0`);
  - upper bounds and compound requirements;
  - `engine:`, `file:` and `patchlevel:` options;
  - patchlevel suffixes;
  - more than one `ruby` line.
- The value handed to setup-ruby is only ever digits and dots (`X.Y` or
  `X.Y.Z`). The echoed Gemfile line is one line, truncated, with control
  characters replaced.
- A Gemfile with no `ruby` line keeps today's default, `3.3`.
- `gate.yml` and `record.yml` are unchanged. Both already stop the step when
  `ruby-version` exits non-zero.
- Suite version `0.2.2`.

## Non-goals

- Changing greeter-cli's Gemfile, or any greeter-core, greeter-cli or
  greeter-http code. The `~> 3.3.5` line is valid Bundler and stays as is.
- Supporting Ruby engines other than MRI, `.ruby-version` files, or
  `patchlevel:` pins.
- Job timeouts and showing Bundler's output during `bundle install` (the earlier
  record-run hang). That is a separate change.
- Any change to features, step definitions, the port, or the drivers.

## Channels affected

- **cli**: fixed. Its gate and record runs set up a Ruby that satisfies its
  Gemfile again.
- **http**: unaffected. A service channel never reads a Gemfile.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `acceptance-gate`: adds a requirement that an artifact channel is gated under
  a Ruby that satisfies its own declared requirement, with safe translation, a
  default when none is declared, and a fail-closed refusal naming an
  untranslatable line.

## Impact

- **Code**: `bin/cli-release` (`CliRelease.ruby_version` and the `ruby-version`
  subcommand's error path).
- **Tests**: a new `spec/cli_release_spec.rb`. `acceptance-gate` is a tooling
  capability, so its new scenarios are verified by RSpec and have no Cucumber
  scenarios (`.kiro/steering/scenario-traceability.md`).
- **Docs**: the README's gate section and the design notes.
- **Version**: `lib/greeter_acceptance/version.rb` goes to `0.2.2`. The record
  workflow checks it against the suite tag.
- **Semver**: patch, `v0.2.2`. It fixes a broken path; no scenario or port method
  changes. A Gemfile with a bare `ruby 'X.Y'` used to reach `bundle install` and
  fail there. It now fails earlier and names the line, so no working candidate
  starts failing.
- **Consumers**:
  - Record mode always runs the latest suite tag, so cli records are fixed as
    soon as `v0.2.2` is tagged.
  - The gate runs the caller's pinned `ACCEPTANCE_REF`, so greeter-cli must bump
    `ACCEPTANCE_REF` to `v0.2.2` before its gate works again.
  - greeter-http need not bump.
