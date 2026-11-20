## ADDED Requirements

### Requirement: Every requirement has a verifying test
Every known `### Requirement:` heading SHALL have a verifying test: for a tooling
capability, an RSpec example tagged `requirement: '<slug>'`; for `greeting`, a
Cucumber scenario carrying the tag that `openspec/requirement-tags.yml` maps to
the slug. A slug is the heading lowercased with each run of characters other than
a-z and 0-9 replaced by one `-` and the ends trimmed. A requirement with no
verifying test SHALL fail the suite, naming it and its spec file.

#### Scenario: Slug rule turns headings into slugs
- **WHEN** the slug function is given the headings in the slug table (for example `A channel greets a valid guest`, `Record mode uses the latest published suite version`, and this repo's real requirement and scenario headings)
- **THEN** it returns `a-channel-greets-a-valid-guest`, `record-mode-uses-the-latest-published-suite-version`, and the expected slug for every other row, with no camel-case splitting
- Maps to: `spec/support/slug_spec.rb`

#### Scenario: Tooling requirement with no tagged example fails and is named
- **WHEN** the trace-check runs against a fixture `spec.md` containing a tooling requirement that no example is tagged with
- **THEN** it fails with a message naming that requirement's slug and the fixture file
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: Greeting requirement with no mapped Cucumber tag fails and is named
- **WHEN** the trace-check runs against a fixture channel-behaviour requirement whose mapped tag is carried by no Cucumber scenario
- **THEN** it fails with a message naming the requirement slug, the mapped tag and the fixture file
- Maps to: `spec/trace_check_spec.rb`

### Requirement: Tagged tests must match a requirement
An RSpec example whose `requirement:` slug matches no known requirement, or whose
`scenario:` slug is not a scenario of its requirement, SHALL fail the suite,
naming the slug and file. Known headings come from `openspec/specs/**/spec.md`
and the ADDED and MODIFIED sections of non-archived changes. A Cucumber
`@requirement-*` tag that is not a value in `openspec/requirement-tags.yml` SHALL
also fail the suite.

#### Scenario: Unknown requirement slug fails and is named
- **WHEN** the trace-check runs with an example tagged with the requirement slug `no-such-requirement`
- **THEN** it fails with a message naming `no-such-requirement` and the example's file
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: Scenario slug is matched only within its requirement
- **WHEN** the trace-check runs with an example whose scenario slug exists only under a different requirement, and another whose scenario slug equals its own requirement's slug
- **THEN** it fails naming the first example's scenario, requirement and file, and reports no problem for the second
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: Requirements in in-flight changes are known
- **WHEN** the trace-check also reads change deltas and an example is tagged with a requirement or scenario found only in an ADDED or MODIFIED section of a change that is not archived, or found only in an archived change, or only in a REMOVED or RENAMED section
- **THEN** the first is known and reports no problem, and the others are reported as unknown with the example's file and line
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: A Cucumber requirement tag outside the map fails and is named
- **WHEN** a fixture feature carries `@requirement-greeting-unmapped` and the map has no such value
- **THEN** the trace-check fails naming `greeting-unmapped` and the feature file
- Maps to: `spec/trace_check_spec.rb`

### Requirement: The requirement-tag map covers the greeting headings
`openspec/requirement-tags.yml` SHALL map the slug of every `greeting`
requirement heading to the existing `@requirement-` tag suffix that verifies it,
and SHALL contain no key that is not a heading slug. The existing Cucumber tags
SHALL NOT be renamed.

#### Scenario: Every greeting heading maps to a tag that exists
- **WHEN** the trace-check reads the real `openspec/requirement-tags.yml`, `openspec/specs/greeting/spec.md` and `features/*.feature`
- **THEN** each of the five greeting heading slugs is a key, each value is carried by a Cucumber scenario, and there are no other keys
- Maps to: `spec/trace_check_spec.rb`

#### Scenario: A key that is not a heading slug fails and is named
- **WHEN** the trace-check runs with a map key that matches no heading in the fixture spec
- **THEN** it fails naming that key and the map file
- Maps to: `spec/trace_check_spec.rb`

### Requirement: Repo trace contains only slugs, statuses, locations and run metadata
The formatter SHALL write a file in schema `greeterhq.repo-trace.v1` with one
result per example tagged with both `requirement` and `scenario`. It SHALL NOT
write example descriptions, failure messages, or any other field, because
descriptions can contain guest names. It SHALL NOT read or write
`tmp/traceability.json`.

#### Scenario: Formatter writes the v1 document
- **WHEN** a suite with one passing and one failing tagged example is run with the formatter
- **THEN** the file has `schema` `greeterhq.repo-trace.v1`, `repo` `greeter-acceptance`, `sha` (`GITHUB_SHA` or `git rev-parse HEAD`), `recorded_at` (UTC ISO 8601), `run_id` (`GITHUB_RUN_ID` or `null`), and two `results` with statuses `passed` and `failed`, `source` `rspec`, and `spec/...rb:LINE` locations
- Maps to: `spec/support/repo_trace_formatter_spec.rb`

#### Scenario: Formatter tells skipped from pending
- **WHEN** a suite with one example marked `skip` and one marked `pending`, both tagged, is run with the formatter
- **THEN** the skipped example has status `skipped` and the pending example has status `pending`
- Maps to: `spec/support/repo_trace_formatter_spec.rb`

#### Scenario: Formatter refuses malformed values
- **WHEN** a tagged example has a requirement or scenario value that is not a lowercase slug (for example `Alice Smith`), or the environment supplies a `GITHUB_SHA` that is not 40 hex characters or a `GITHUB_RUN_ID` that is not digits
- **THEN** the formatter raises an error naming the field and writes no file
- Maps to: `spec/support/repo_trace_formatter_spec.rb`

#### Scenario: Formatter omits descriptions
- **WHEN** a tagged example whose description contains `Alice Smith` is run with the formatter
- **THEN** the written file does not contain `Alice Smith` and each result has exactly the keys `requirement`, `scenario`, `status`, `source`, `location`
- Maps to: `spec/support/repo_trace_formatter_spec.rb`

#### Scenario: Formatter leaves the per-channel run file alone
- **WHEN** a tagged suite is run with the formatter while `tmp/traceability.json` exists
- **THEN** that file's bytes are unchanged and the formatter wrote only to the `REPO_TRACE_PATH` file
- Maps to: `spec/support/repo_trace_formatter_spec.rb`

