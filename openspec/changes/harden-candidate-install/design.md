# Design

## Context

Findings S7 and S8 from the security review in
`fix-candidate-ruby-version/design.md` (Security Considerations).

How an artifact channel's candidate is installed today, in both workflows:

```
fetch / extract      bin/cli-release      no candidate code runs
ruby-version         bin/cli-release      reads the Gemfile as text
setup-ruby           action
install              bin/cli-release      bundle install  ← evaluates the Gemfile (Ruby)
go back to suite     action
[record only] Look up when the release was published   env: GH_TOKEN ← after candidate code
Run the suite        cucumber, runs the candidate
```

- **The token after candidate code (S8):** any process can append to the files
  named by `$GITHUB_PATH` and `$GITHUB_ENV`, and later steps pick that up. A
  Gemfile that prepends a directory holding a fake `gh` would receive
  `GH_TOKEN` in the lookup step. The token is the run job's `github.token`, with
  `contents: read` on this repository for the life of the job.
- **The install is not frozen (S7):** `CliRelease.install` runs
  `bundle install` with `CLEAN_ENV`, which unsets four Bundler and Ruby
  variables but does not freeze the lockfile. Checked with Bundler 4.0.22:
  - with `BUNDLE_FROZEN=true`, a missing lockfile is refused ("The frozen setting
    requires a lockfile", exit 16), and so is a stale one ("You have added to the
    Gemfile: …", exit 16);
  - without it, the stale lockfile is re-resolved and the install succeeds.

The port and the drivers are not involved:

```
before: channel, capabilities, supports?, greet, count_for, last_error,
        last_native_error, native_idiom_for?, build_info
after:  unchanged
```

`CliDriver` and `HttpDriver` are unchanged.

## Goals / Non-Goals

**Goals:**
- In each workflow job, no step that references a token or secret runs after
  the first step that runs candidate code. A spec enforces this.
- A candidate is installed exactly as its lockfile pins, or not at all.

**Non-Goals:**
- Sandboxing candidate code from the runner's file commands.
- Job timeouts and Bundler output.
- Any change to greeter-cli.

## Decisions

### Move the release-time lookup before the fetch

"Look up when the release was published" moves to just before "Fetch the release
(checksum and tag checked)". Nothing else about the step changes: its `if`,
`continue-on-error`, `env` and output `at` stay as they are, and "Run the suite"
still reads `steps.released.outputs.at`. At that point only the suite tag's
checkout and setup-ruby have run, so no candidate code has had a chance to touch
`PATH`. The workflow file runs from `main`, so this takes effect on merge.

Rejected alternatives:
- **Unset `GITHUB_PATH` and `GITHUB_ENV` for `bundle install`.** The file-command
  files live at predictable paths under `$RUNNER_TEMP`, so unsetting the
  variables only hides the paths.
- **Look the time up in the resolve job and pass it in the matrix.** This also
  works, but it widens the resolve job (a token and a call per cli entry) to
  fix an ordering problem.

### Freeze the install

`CLEAN_ENV` gains `'BUNDLE_FROZEN' => 'true'`, so the candidate's own
`Gemfile.lock` is authoritative. `BUNDLE_DEPLOYMENT` is not used: it also
changes the install path (`vendor/bundle`), which the launcher does not expect.
Frozen mode is the part that matters.

On failure, `install` raises today's message with a reason added:

```
bundle install failed in <dir> (the Gemfile.lock must be present and match the Gemfile)
```

Bundler's own output is still not shown. That belongs with the separate
Bundler-output change.

### The ordering spec

`spec/workflow_token_order_spec.rb` loads `record.yml` and `gate.yml` with
`YAML.safe_load_file`. For each job:

- **The boundary** is the first step that runs candidate code: a `run:` that
  calls `bin/cli-release install`. A job with no such step is skipped.
- **The check:** no step after the boundary may reference `secrets.`,
  `github.token` or `steps.<id>.outputs.token` in its `env:`, `with:` or `run:`.
- **The listing:** the check names every offending step, so a later edit that
  reintroduces the gap fails with a clear message.
- **The positive case:** the release-time lookup in `record.yml` comes before
  the fetch.

Before the move, `record.yml` fails the check. `gate.yml` already passes,
because it holds no token.

### What the check does not cover

Actions get the runner's `ACTIONS_RUNTIME_TOKEN` implicitly. After the install
these are `ruby/setup-ruby` (with `bundler-cache`) and
`actions/upload-artifact`. That token is scoped to this run's cache and
artifacts. The candidate could already forge its own trace, and the publish
stage treats the trace as untrusted data. This is accepted and recorded here; a
YAML check cannot see implicit tokens.

### Version

`GreeterAcceptance::VERSION` becomes `'0.3.0'`. This is a minor bump: a candidate
that used to install without a matching lockfile now fails.

## Risks / Trade-offs

- [A future cli release ships without `Gemfile.lock`] Its gate and record runs
  fail at install → intended. The message names the reason. A record run still
  updates `deployed.json` with no result.
- [The lockfile's `BUNDLED WITH` differs from the runner's Bundler] Frozen
  mode does not refuse a different Bundler version → no effect.
- [Lookup before fetch fails] It is `continue-on-error`, as before, and
  `released_at` is recorded as null → unchanged behaviour.

## Migration Plan

1. Land after `fix-candidate-ruby-version` (`v0.2.2`). Both edit
   `bin/cli-release` and `spec/cli_release_spec.rb`.
2. Merge to `main`. The `record.yml` reorder is live from then on.
3. Tag `v0.3.0`. Record mode installs frozen from its next run.
4. Outside this repo, not tracked here: greeter-cli bumps `ACCEPTANCE_REF` to
   `v0.3.0`.

## Open Questions

None.
