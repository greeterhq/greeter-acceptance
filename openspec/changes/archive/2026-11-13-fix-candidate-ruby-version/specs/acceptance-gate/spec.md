# Spec Delta

## ADDED Requirements

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
