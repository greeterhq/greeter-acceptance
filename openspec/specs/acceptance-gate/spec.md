# acceptance-gate Specification

## Purpose

Defines the read-only gate that a channel's release pipeline calls to prove a
candidate release passes the channel-neutral suite before it is published or
promoted, using the suite version the channel has pinned.

## Requirements

### Requirement: The gate is a read-only reusable workflow

The gate SHALL be callable from another repository's release workflow, SHALL
run with read-only repository permissions, and SHALL NOT write to any ledger
branch.

#### Scenario: A release workflow calls the gate

- **WHEN** a channel's release workflow calls the gate
- **THEN** the gate runs the suite and reports its result to the caller

#### Scenario: A gate run leaves the ledgers unchanged

- **WHEN** a gate run completes, whether it passes or fails
- **THEN** no ledger branch has changed

### Requirement: The gate runs the caller's pinned suite version

The gate SHALL run the suite version named by the caller's pinned acceptance
reference, and SHALL fail when the caller supplies no reference.

#### Scenario: A pinned reference

- **WHEN** the caller supplies an acceptance reference
- **THEN** the gate runs the suite at exactly that reference

#### Scenario: No reference supplied

- **WHEN** the caller supplies no acceptance reference
- **THEN** the gate fails before running any scenario

### Requirement: An artifact channel is gated on its built artifact

A channel distributed as an artifact SHALL be gated against the artifact its
release pipeline built, before that artifact is published.

#### Scenario: The gate receives the built artifact

- **WHEN** the caller supplies the artifact it built
- **THEN** the gate runs the suite against that artifact

#### Scenario: The gate fails

- **WHEN** the gate fails for an artifact channel
- **THEN** it reports failure to the caller so that the release does not proceed

### Requirement: A service channel is gated at its stage environment

A channel deployed as a service SHALL be gated against its stage environment,
with the target resolved from committed configuration.

#### Scenario: The gate targets the stage environment

- **WHEN** the gate runs for a service channel
- **THEN** it runs the suite against that channel's stage target from the
  committed configuration

### Requirement: The gate verifies the version it tested

The gate SHALL fail when the build information observed during the run does not
match the candidate version the caller supplied, or cannot be observed, unless
the caller explicitly allows an unverified run.

#### Scenario: The observed version matches the candidate

- **WHEN** the observed build information equals the candidate version
- **THEN** the gate's version check passes

#### Scenario: The observed version differs from the candidate

- **WHEN** the observed build information differs from the candidate version
- **THEN** the gate fails and names both versions

#### Scenario: The version cannot be observed

- **WHEN** no build information can be observed and the caller has not allowed an
  unverified run
- **THEN** the gate fails

#### Scenario: An unverified run is explicitly allowed

- **WHEN** no build information can be observed and the caller has allowed an
  unverified run
- **THEN** the gate's version check passes and the result is marked unverified

### Requirement: The gate fails only on failed or error results

The gate SHALL fail when any scenario is recorded as failed or error, and SHALL
NOT fail because a scenario is not applicable.

#### Scenario: A failed or errored scenario

- **WHEN** any scenario is recorded as failed or error
- **THEN** the gate fails

#### Scenario: Only not-applicable scenarios were skipped

- **WHEN** every other scenario passes and some are not applicable
- **THEN** the gate passes

### Requirement: An artifact channel is gated under the Ruby its artifact declares

The gate SHALL set up a Ruby that satisfies the single Ruby requirement the
candidate artifact declares in its Gemfile, before installing the candidate.
An exact version SHALL be used as given. A pessimistic (`~>`) or minimum (`>=`)
requirement SHALL select the lowest major.minor series it allows, of which the
newest patch is installed. With no declared requirement, the gate SHALL use the
default Ruby, 3.3.

#### Scenario: An exact Ruby is pinned

- **WHEN** a candidate's Gemfile pins an exact Ruby version, such as `3.3.5` or
  `= 3.3.5`
- **THEN** the gate sets up that Ruby

#### Scenario: A pessimistic or minimum requirement

- **WHEN** a candidate's Gemfile gives a `~>` or `>=` requirement, such as
  `~> 3.3.5`, `~> 3.3` or `>= 3.3.5`
- **THEN** the gate sets up the lowest major.minor series that requirement
  allows, here `3.3`, and its newest patch is installed

#### Scenario: A trailing comment on the ruby line

- **WHEN** a candidate's Gemfile `ruby` line ends with a comment after the
  version, such as `ruby '3.3.5' # pin`
- **THEN** the comment is ignored and the gate sets up the version the line gives

#### Scenario: No Ruby is declared

- **WHEN** a candidate's Gemfile has no `ruby` line, or only a commented-out one
- **THEN** the gate uses the default Ruby, 3.3

### Requirement: An untranslatable Ruby requirement fails the gate before install

The gate SHALL fail before installing the candidate, naming the offending
Gemfile line, when the declared Ruby requirement cannot be translated to one
safe version. This covers a bare major.minor (exact or with `=`), any other
operator, a compound requirement, engine, file or patchlevel options, a version
with a suffix, and more than one `ruby` line.

#### Scenario: A requirement that cannot be translated

- **WHEN** a candidate's Gemfile declares a Ruby requirement such as `< 4`,
  `~> 3`, `'>= 3.3', '< 3.5'`, `'3.3.5', engine: 'jruby'`,
  `file: '.ruby-version'` or `3.3.5p100`
- **THEN** the gate fails before installing the candidate and names the line

#### Scenario: A bare major.minor

- **WHEN** a candidate's Gemfile declares `ruby '3.3'` or `ruby '= 3.3'`, which
  Bundler reads as exactly 3.3.0
- **THEN** the gate fails before installing the candidate and names the line

#### Scenario: More than one ruby line

- **WHEN** a candidate's Gemfile has more than one `ruby` line
- **THEN** the gate fails before installing the candidate

### Requirement: An unreadable Gemfile fails the gate before install

The gate SHALL read a candidate's Gemfile only when it is a regular file of at
most 64 KiB holding valid UTF-8, and SHALL otherwise fail before installing the
candidate. The failure SHALL give the reason without echoing the file's
content. The gate SHALL NOT follow a link, wait on a special file, or read past
the size limit to decide this.

#### Scenario: The Gemfile is a link or a special file

- **WHEN** a candidate's Gemfile is a symbolic link or a named pipe
- **THEN** the gate fails before installing the candidate, says the Gemfile is
  not a regular file, and neither reads the link's target nor waits on the pipe

#### Scenario: The Gemfile is too large

- **WHEN** a candidate's Gemfile is larger than 64 KiB
- **THEN** the gate fails before installing the candidate and says the Gemfile
  is too large

#### Scenario: The Gemfile is not valid UTF-8

- **WHEN** a candidate's Gemfile contains bytes that are not valid UTF-8
- **THEN** the gate fails before installing the candidate, says the Gemfile is
  not valid UTF-8, and echoes none of its bytes

### Requirement: Only a plain version reaches the Ruby installer

The value the gate hands to the Ruby installer SHALL only ever be digits and
dots in the form X.Y or X.Y.Z, whatever the Gemfile contains. When the gate
names an offending Gemfile line, it SHALL show it as one line of at most 80
characters, with control characters replaced.

#### Scenario: A Gemfile line carrying shell text

- **WHEN** a candidate's Gemfile declares `ruby '3.3; rm -rf /'`
- **THEN** the gate fails before installing the candidate and nothing from the
  line is handed to the Ruby installer

#### Scenario: A Gemfile line with control characters

- **WHEN** an untranslatable `ruby` line contains a tab, an escape character or
  a bidirectional override
- **THEN** the line the gate names is a single line with each of those
  characters replaced by `?`, truncated to 80 characters
