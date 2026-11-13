# Design

## Context

An artifact channel (cli) has to run under the Ruby its own Gemfile declares,
through its own bundle. Both workflows do this the same way:

```
gate.yml   "Unpack the candidate and read the Ruby it declares"
record.yml "Read the Ruby the release declares"
    declared="$(ruby bin/cli-release ruby-version "$dir")"
    echo "ruby=${declared:-3.3}" >> "$GITHUB_OUTPUT"
→ ruby/setup-ruby  with  ruby-version: <that output>
→ bin/cli-release install   (bundle install under that Ruby)
```

Today `CliRelease.ruby_version(dir)` returns whatever is between the quotes of
the first line matching `/^\s*ruby\s+['"]([^'"]+)['"]/`. That works for
`ruby '3.3.5'` (greeter-cli v0.1.2). It breaks for `ruby '~> 3.3.5'`: setup-ruby
receives `~> 3.3.5` and fails with "Unknown engine ~> 3.3.5". The value is also
unchecked text from an untrusted artifact flowing into a workflow input.

The port and the drivers are not involved. No port method is added or changed:

```
before: channel, capabilities, supports?, greet, count_for, last_error,
        last_native_error, native_idiom_for?, build_info
after:  unchanged
```

`CliDriver` and `HttpDriver` are unchanged. The fix is entirely in
`bin/cli-release`, which runs before any driver exists.

## Goals / Non-Goals

**Goals:**
- `ruby-version` prints a version setup-ruby accepts and that satisfies the
  Gemfile, or prints nothing when the Gemfile declares no Ruby.
- Anything else fails closed, before `bundle install`, naming the line.
- The printed value can only ever be `X.Y` or `X.Y.Z`.

**Non-Goals:**
- Changing greeter-cli or its Gemfile.
- Other engines, `.ruby-version` files, or patchlevel pins.
- Job timeouts and Bundler output (the earlier record-run hang).
- Any edit to `gate.yml`, `record.yml`, `features/` or the step definitions.

## Decisions

### Finding the ruby line

Each Gemfile line is considered after leading whitespace is stripped:

- A line starting with `#` is a comment and is ignored.
- A line is a ruby line when it starts with `ruby` followed by a space or `(`.
  `rubygems_version`, `ruby_version = …` and the like are not ruby lines.
- No ruby line: return `nil`. The CLI prints an empty line, `$(...)` strips it,
  and the workflows fall back to `3.3` as they do today.
- More than one ruby line fails, even if they agree. Bundler would only honour
  one, and picking one here would be a guess.

### Accepted line shape

A ruby line is accepted only in one of these shapes:

```
ruby <spaces> <quoted> [<spaces>] [# comment]
ruby(<spaces?> <quoted> <spaces?>) [<spaces>] [# comment]
```

- `<quoted>` is one string in single or double quotes, with matching quotes,
  no escapes and no quote characters inside.
- Trailing spaces are allowed.
- A trailing comment after the closing quote or paren is allowed and ignored.

Anything else fails: a second requirement (`'>= 3.3', '< 3.5'`), options
(`engine:`, `engine_version:`, `file:`, `patchlevel:`), interpolation, a
variable, or unbalanced quotes. The grammar is checked with one anchored regular
expression. The Gemfile is never evaluated.

### Translation rules

The quoted string, with optional spaces between operator and version:

| Requirement | Result | Why |
| --- | --- | --- |
| `X.Y.Z` | `X.Y.Z` | exact pin |
| `= X.Y.Z` | `X.Y.Z` | exact pin |
| `~> X.Y.Z` | `X.Y` | allows X.Y.Z up to X.(Y+1); newest X.Y patch satisfies it |
| `~> X.Y` | `X.Y` | allows X.Y up to (X+1).0; lowest series is X.Y |
| `>= X.Y.Z` | `X.Y` | lowest series it allows; newest X.Y patch satisfies it |
| `>= X.Y` | `X.Y` | lowest series it allows |
| `X.Y`, `= X.Y` | fail | see below |
| anything else | fail | `<`, `<=`, `>`, `!=`, `~> X`, suffixes such as `p100` or `.preview1`, … |

A series `X.Y` is what setup-ruby resolves to its newest patch. Using the lowest
series a requirement allows keeps the run on the oldest Ruby the author
supports, the conservative choice for an acceptance check.

**A bare `X.Y` (or `= X.Y`) is refused.** Bundler reads `ruby '3.3'` as exactly
3.3.0, not as any 3.3. Checked with Bundler 4.0.22 on Ruby 3.3.13: a Gemfile with
`ruby '3.3'` is refused by `bundle install` with "Your Ruby version is 3.3.13,
but your Gemfile specified 3.3". No setup-ruby value both satisfies that
Gemfile and is installable as anything other than 3.3.0. So passing `3.3`
through would only move the failure into `bundle install`, without naming the
line. The failure message tells the author what is wrong. The author should pin
`X.Y.Z`, or use `~> X.Y` / `~> X.Y.Z` to allow a series.

### The output check

Whatever the translation returns must match `/\A\d+\.\d+(\.\d+)?\z/`, or the
call fails. The translation rules already guarantee this. The final check
exists so that no future rule can let anything else reach setup-ruby.

### Failure message

Every refusal raises `CliRelease::Failure` with:

```
unsupported ruby requirement in Gemfile: <line>
```

`<line>` is the offending Gemfile line with leading and trailing whitespace
stripped. Every character outside printable ASCII (`\x20`–`\x7E`) is replaced
with `?`. That covers control characters such as tab and escape, and Unicode
format characters such as bidirectional overrides (see Security
Considerations, S2). The result is truncated to 80 characters. For "more than one ruby
line", `<line>` is the second ruby line found.

The CLI's existing rescue prints `bin/cli-release: <message>` on stderr and
exits 1. The printed line is untrusted text from the artifact. It is a single
line, and it is preceded by `bin/cli-release:`, so it can never start a GitHub
workflow command (`::…`). Replacing control characters keeps terminal escapes
out of the log.

### No workflow change

Both workflows run `run:` steps as `bash -e {0}`. `declared="$(…)"` is a plain
assignment, so its exit status is the command's and `-e` stops the step. In the
gate this happens before "Set up the Ruby the candidate declares" and before
"Install the candidate". In record mode it happens before "Install the release".
The step log shows the `bin/cli-release:` message.

### record.yml uses the same reader

The record workflow's "Read the Ruby the release declares" step calls the same
`bin/cli-release ruby-version`. Record mode runs the latest suite tag, so cli
records are fixed by this change once `v0.2.2` is tagged, with no edit to
`record.yml`. When a release's Gemfile is refused, the record run job fails
before the suite runs. The publish job then records the deployment with no
result, as it does for any run that produced no result.

### Bundler is the second line of defence

`bundle install` checks the running Ruby against the Gemfile's `ruby`
requirement and refuses a mismatch (exit 18). If the version chosen here ever
fails to satisfy the Gemfile, Bundler stops the install before the candidate
runs. The table above is designed so that check passes. One case relies on it:
a requirement whose patch is newer than the newest patch of its series
(`~> 3.3.99`).

### Version

`GreeterAcceptance::VERSION` becomes `'0.2.2'`. The record workflow checks it
equals the suite tag. This is a patch release: a fix with no scenario or port
change.

### Testing approach

`spec/cli_release_spec.rb` loads the script with
`load File.expand_path('../bin/cli-release', __dir__)`. The script's
`$PROGRAM_NAME == __FILE__` guard keeps the CLI from running, so the module is
exercised directly. Each example writes a fixture Gemfile into a
`Dir.mktmpdir`.

Examples:
- **Accepted**, one per form: `3.3.5`, `= 3.3.5`, `~> 3.3.5`, `~>3.3.5`, `~> 3.3`,
  `>= 3.3.5`, `ruby('3.3.5')`, double quotes, and a trailing comment.
- **No requirement**: no ruby line, and a commented-out ruby line.
- **Refused**: `3.3`, `= 3.3`, `< 4`, `~> 3`, `'>= 3.3', '< 3.5'`,
  `'3.3.5', engine: 'jruby'`, `file: '.ruby-version'`, `3.3.5p100`,
  `3.3; rm -rf /`, and two ruby lines.
- **Message format**: a refused line containing a tab and an escape character,
  expected as one line with `?` in their place and at most 80 characters.
- **The real script**, run with `Open3` under `RbConfig.ruby`: `~> 3.3.5` prints
  `3.3\n` and exits 0, and `< 4` exits 1 with "unsupported ruby requirement" on
  stderr.

## Security Considerations

The Gemfile comes from an untrusted artifact: a caller's build in the gate, a
published release in record mode. `ruby-version` reads it in a job that holds
no write credential, and no token is in that step's environment. Findings from
the review (OWASP API Top 10, input reflection, error leakage, log injection,
IAM scope, dependency confusion on greeter-core):

| # | Area | Finding | Severity | Resolution |
| --- | --- | --- | --- | --- |
| S1 | API10 unsafe consumption; injection | Today the requirement text flows unchecked into setup-ruby's `ruby-version` input. | High (the bug) | This change: the grammar check plus the `\A\d+\.\d+(\.\d+)?\z` output check. Only digits and dots reach setup-ruby. |
| S2 | Input reflection; log injection | The failure message echoes the Gemfile line. Replacing `[[:cntrl:]]` alone lets Unicode format characters through: a bidi override `U+202E` survives (checked on Ruby 3.3.13) and can make a refused line read differently in the log. | Low | Code, task 2.3: replace everything outside printable ASCII. One line, the `bin/cli-release:` prefix (no `::` workflow command can start it), 80 characters. |
| S3 | API4 unrestricted resource consumption | The tarball may hold a `Gemfile` that is a symlink or a FIFO. `tar -xzf` extracts symlinks as they are (checked: `Gemfile -> /dev/zero` extracts unchanged), and `single_top_level` checks only paths. `File.read` would then follow the link, never finish on `/dev/zero`, or block on a FIFO. With no job timeout, that holds a runner for 6 hours. A very large regular Gemfile costs memory. | Medium | Code, task 2.4: refuse a Gemfile that is not a regular file (`lstat`, then open with `NOFOLLOW` and `NONBLOCK`). Refuse one larger than 64 KiB. Read at most the limit. |
| S4 | Error leakage | A Gemfile that is not valid UTF-8 makes the line match raise `ArgumentError: invalid byte sequence in UTF-8` (checked). The CLI does not rescue it, so the run fails closed but prints a Ruby backtrace with runner paths and no reason a person can act on. | Low | Code, task 2.4: check the encoding first and raise `CliRelease::Failure` with a fixed message. The message echoes nothing from the file. |
| S5 | Regular-expression cost | A long crafted line could make a backtracking pattern slow. Ruby 3.3 memoizes regexes without back-references or lookaround, and `Regexp.timeout` is unset. | Info | Keep the grammar pattern anchored, with no back-references or lookaround. S3's 64 KiB cap bounds the input. No separate task. |
| S6 | IAM scope | The steps that run `ruby-version` (gate "Unpack the candidate…", record "Read the Ruby the release declares") run with `contents: read` and no token in `env`. The value goes to setup-ruby, never into a shell command. | None | No change. |
| S7 | Dependency confusion on greeter-core | The suite does not depend on greeter-core (black-box drivers, stdlib-only `bin/`). greeter-cli's `Gemfile.lock` resolves `greeter-core (0.1.3)` from `https://rubygems.org/` with a sha256 checksum, the one source its Gemfile names. `install` runs `bundle install` without frozen mode, so a lockfile out of step with its Gemfile would be re-resolved instead of refused. | Low; outside this change | Not part of `ruby-version`. Follow-up: run `install` with `BUNDLE_FROZEN=true` so the candidate's lockfile is used exactly. No change is proposed to greeter-cli. |
| S8 | IAM scope (outside this change) | `bundle install` evaluates the candidate's Gemfile, which is Ruby code. That code can append to `$GITHUB_PATH` or `$GITHUB_ENV`. In `record.yml` the next steps include "Look up when the release was published", which has `GH_TOKEN` (the job's read-only `github.token`) in `env`. A planted `gh` on `PATH` could read it. | Medium; outside this change | Not part of `ruby-version`, and this change does not edit workflows. Follow-up: move the release-time lookup before "Fetch the release", so no step after candidate code holds a token. |
| — | OWASP API1–3, 5–7, 9 | Authorisation, authentication, property-level access, function-level access, business flows, SSRF and inventory. `ruby-version` is a local CLI over one file, with no API surface, identity or outbound request. | N/A | — |

Every finding inside this change either fails closed or is fixed by tasks 2.3
and 2.4. S7 and S8 are outside this change's scope. They are listed under
Workflow follow-up in tasks.md for a separate change.

## Risks / Trade-offs

- [Newest patch below the requirement] `~> 3.3.99` or `>= 3.3.99` translates to
  `3.3`. If setup-ruby's newest 3.3 is older, `bundle install` refuses it →
  accepted: Bundler fails closed and names both versions. Pinning `X.Y.Z` avoids
  it.
- [Lowest series, not newest] `>= 3.3` runs on 3.3 even when 3.4 exists →
  intended: the oldest supported series is the stricter check. An author who
  wants a newer series raises the lower bound.
- [Bare `X.Y` refused] A Gemfile that Bundler accepts on Ruby X.Y.0 is refused
  here → accepted: that Gemfile pins 3.3.0, which is almost never the intent,
  and the message names the line.
- [Truncation] An 80-character limit can cut off the end of a long line → the
  start of the line, which carries `ruby` and the requirement, is what matters.
- [Exact patch availability] An exact `X.Y.Z` must be installable by setup-ruby on
  the runner image. This is why the run and gate jobs use `ubuntu-24.04`. No
  change here.

## Migration Plan

1. Land the spec, then the `bin/cli-release` change and the version bump.
2. Tag `v0.2.2`. Record mode picks it up on its next run.
3. Outside this repo, not tracked here: greeter-cli bumps its `ACCEPTANCE_REF`
   to `v0.2.2` so its gate uses the fix.

Rollback: a gate caller can pin `ACCEPTANCE_REF` back to `v0.2.1`, and record
mode would need `v0.2.2` deleted, but the old behaviour is the bug, so neither
is expected.

## Open Questions

None. The `X.Y` decision, trailing comments, and the message format were settled
before this design was written.
