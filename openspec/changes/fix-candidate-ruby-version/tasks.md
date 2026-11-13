# Tasks

Notes for whoever applies this change:
- Only these files change: `bin/cli-release`, the new `spec/cli_release_spec.rb`,
  `lib/greeter_acceptance/version.rb`, and docs.
- `.github/workflows/gate.yml`, `.github/workflows/record.yml`, `features/` and
  the step definitions stay untouched.
- The port and the drivers are unchanged, so there are no new feature, step
  definition or driver-contract examples.

## 1. Red tests

- [ ] 1.1 Write `spec/cli_release_spec.rb`.
  - **Setup:** load the script with
    `load File.expand_path('../bin/cli-release', __dir__)`, and write each
    fixture Gemfile into a `Dir.mktmpdir`.
  - **Accepted, one example per row:** `'3.3.5'` → `3.3.5`, `'= 3.3.5'` →
    `3.3.5`, `'~> 3.3.5'` → `3.3`, `'~>3.3.5'` → `3.3`, `'~> 3.3'` → `3.3`,
    `'>= 3.3.5'` → `3.3`, `ruby('3.3.5')` → `3.3.5`, double quotes →
    `3.3.5`, and `ruby '3.3.5' # pin` → `3.3.5`.
  - **No requirement:** no ruby line → nil, and a commented-out ruby line → nil.
  - **Refused**, each raising `CliRelease::Failure` with "unsupported ruby
    requirement in Gemfile: <line>": `'3.3'`, `'= 3.3'`, `'< 4'`, `'~> 3'`,
    `'>= 3.3', '< 3.5'`, `'3.3.5', engine: 'jruby'`, `file: '.ruby-version'`,
    `'3.3.5p100'`, `'3.3; rm -rf /'`, and two ruby lines.
  - **Message format:** a refused line containing a tab and an escape character
    is named as one line, with `?` for each, at most 80 characters.
  - **The real script**, run with `Open3` under `RbConfig.ruby`: `'~> 3.3.5'`
    prints `"3.3\n"` and exits 0; `'< 4'` exits 1 with "unsupported ruby
    requirement" on stderr.
  - **Verify red for the right reason:** run `bundle exec rspec
    spec/cli_release_spec.rb` and check the failures are expectation failures,
    not syntax or load errors:
    - the `~>` and `>=` examples get the raw requirement (e.g. `"~> 3.3.5"`);
    - the refused examples report that no error was raised;
    - the `'< 4'` script example exits 0.
- [ ] 1.2 Add the security examples from design.md (Security Considerations
  S2–S4) to `spec/cli_release_spec.rb`:
  - **S2:** a refused line containing a bidi override (`U+202E`) is named with
    `?` in its place.
  - **S3:**
    - a `Gemfile` that is a symlink to another file is refused without reading
      the target;
    - a `Gemfile` that is a FIFO is refused without blocking;
    - a regular Gemfile larger than 64 KiB is refused.
  - **S4:** a Gemfile with invalid UTF-8 raises `CliRelease::Failure`, not
    `ArgumentError`, and the message holds none of the file's bytes.

  Use `File.symlink` and `File.mkfifo` in the tmpdir. Give the FIFO example a
  short `Timeout` so a regression fails instead of hanging. Verify red for the
  right reason:
  - the bidi example's message keeps `U+202E`;
  - the symlink example returns the target's requirement;
  - the size example returns a version;
  - the FIFO example times out;
  - the encoding example raises `ArgumentError`.
- [ ] 1.3 Run RuboCop on `spec/cli_release_spec.rb`. Verify no offenses and a
  `frozen_string_literal` magic comment.

## 2. Ruby requirement reader

- [ ] 2.1 In `CliRelease.ruby_version(dir)`, find the ruby lines:
  - strip leading whitespace;
  - skip lines that start with `#`;
  - a ruby line is `ruby` followed by a space or `(`;
  - none → `nil`; more than one → `Failure`.

  Check the line against the accepted shape (one single- or double-quoted
  string, optional parentheses, trailing spaces, optional trailing comment). The
  Gemfile is never evaluated. Verify the no-requirement, two-ruby-lines,
  parentheses, double-quote and trailing-comment examples pass.
- [ ] 2.2 Translate the quoted requirement by the design's table:
  - `X.Y.Z` and `= X.Y.Z` give `X.Y.Z`;
  - `~>` or `>=` with `X.Y.Z` or `X.Y` give `X.Y`;
  - everything else (including `X.Y` and `= X.Y`) fails.

  Then check the result matches `/\A\d+\.\d+(\.\d+)?\z/`, failing otherwise.
  Verify every accepted and refused example passes.
- [ ] 2.3 Build the failure message "unsupported ruby requirement in Gemfile:
  <line>": strip the line, replace every character outside printable ASCII
  (`\x20`–`\x7E`) with `?` (design S2), keep it to one line, and truncate to 80
  characters. Keep the CLI's existing rescue, so
  the script prints `bin/cli-release: …` on stderr and exits 1. Verify the
  tab-and-escape example and both `Open3` examples pass.
- [ ] 2.4 Read the Gemfile safely (design S3–S5), before any line is matched:
  - refuse a Gemfile that `File.lstat` does not report as a regular file;
  - open it with `File::RDONLY | File::NOFOLLOW | File::NONBLOCK` and refuse if
    `stat.file?` is false;
  - read at most 64 KiB + 1 byte, and refuse a larger file;
  - refuse content that is not valid UTF-8.

  Each refusal raises `CliRelease::Failure` with a fixed message that echoes no
  file content: "Gemfile is not a regular file", "Gemfile is larger than 64
  KiB", "Gemfile is not valid UTF-8". Keep the grammar pattern anchored, with
  no back-references or lookaround. Verify every 1.2 example passes and no
  earlier example regresses.
- [ ] 2.5 Update the `ruby-version` line in the script's header comment to
  describe the translation and the failure. Verify all of
  `spec/cli_release_spec.rb` passes and RuboCop reports no offenses for
  `bin/cli-release`.

## 3. Version and docs

- [ ] 3.1 Set `GreeterAcceptance::VERSION` to `'0.2.2'`. Verify
  `ruby -Ilib -rgreeter_acceptance/version -e 'puts GreeterAcceptance::VERSION'`
  prints `0.2.2`.
- [ ] 3.2 In the README's gate section, document which Gemfile `ruby` lines an
  artifact channel may use and what each sets up:
  - exact `X.Y.Z` → that version;
  - `~>` / `>=` → the lowest `X.Y` series;
  - no line → 3.3;
  - why a bare `X.Y` is refused;
  - what a refusal looks like.

  Verify every YAML snippet in the README still parses.

## 4. Verify and docs

- [ ] 4.1 Run the tooling specs with `bundle exec rspec`, and the driver contract
  with `GREETER_CHANNEL=cli` (real greeter-cli launcher) and `GREETER_CHANNEL=http`
  (stage endpoint). Verify everything passes.
- [ ] 4.2 Run `GREETER_CHANNEL=cli bundle exec cucumber` and
  `GREETER_CHANNEL=http bundle exec cucumber`. Check each `tmp/traceability.json`
  against `docs/traceability-schema.md`. Verify the results match the previous
  release: on cli the universal scenarios pass and the capability scenarios are
  not applicable; on http all scenarios pass.
- [ ] 4.3 Check the reader against a real release and the workflow shell:
  - `bin/cli-release fetch` greeter-cli v0.1.2 (Gemfile `ruby '3.3.5'`), then
    `bin/cli-release ruby-version` on it prints `3.3.5`;
  - a copy with its Gemfile line changed to `ruby '~> 3.3.5'` prints `3.3`;
  - the workflow's `declared="$(ruby bin/cli-release ruby-version "$dir")"`
    line, run under `bash -e` against a `'< 4'` Gemfile, stops with exit 1
    before its next command and prints the `bin/cli-release:` message.
- [ ] 4.4 Confirm the files the change must not touch are unchanged. Verify
  `git diff main -- .github/workflows features` is empty.
- [ ] 4.5 Run RuboCop, check `frozen_string_literal` on every Ruby file, and run
  `openspec validate fix-candidate-ruby-version --strict` and
  `openspec validate --all --strict`. Verify all pass.

## Workflow follow-up

- Security findings outside this change's scope (design.md, Security
  Considerations). Each needs its own change:
  - S7 and S8 are planned in the change `harden-candidate-install`. It lands
    after this one.

- Tag `v0.2.2` on `main` after merge. Record mode picks it up on its next run.
- Outside this repo: greeter-cli bumps `ACCEPTANCE_REF` to `v0.2.2` so its gate
  uses the fix.
- Archive the change after review.
