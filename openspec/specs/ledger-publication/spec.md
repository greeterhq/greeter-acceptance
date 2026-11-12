# ledger-publication Specification

## Purpose

Defines how the suite records what each channel's deployed version achieved
against the suite and publishes it to per-environment ledger branches that
tools and people can read, even when channels release independently.

## Requirements

### Requirement: Record mode runs on a channel release, a new suite version, or a manual request

The suite SHALL record results when a channel-released event arrives, when a
new suite version is published, or when a maintainer requests a run manually.
A manual request SHALL accept the same fields as the event, plus an option to
re-run every channel.

#### Scenario: A channel is released

- **WHEN** a channel-released event arrives for one channel
- **THEN** only that channel is tested and recorded

#### Scenario: A new suite version is published

- **WHEN** a new suite version is published
- **THEN** every channel named in the deployed record is tested at its deployed
  version and recorded

#### Scenario: A manual request

- **WHEN** a maintainer requests a manual run with the event's fields
- **THEN** the run behaves as the event would have

#### Scenario: A manual request to re-run every channel

- **WHEN** a maintainer requests a manual run with the re-run option
- **THEN** every channel named in the deployed record is tested and recorded

### Requirement: Record mode uses the latest published suite version

Record mode SHALL run the latest published suite version, not the head of the
default branch.

#### Scenario: Unreleased changes exist on the default branch

- **WHEN** a record run starts and the default branch has changes after the
  latest published suite version
- **THEN** the run uses the latest published suite version

### Requirement: A channel-released event is validated before use

The suite SHALL validate a channel-released event before acting on it: the
channel and environment SHALL be known, and the version and commit identifier
SHALL be well formed. It SHALL refuse an invalid event and publish nothing.

#### Scenario: A valid event

- **WHEN** an event names a known channel and environment with a well-formed
  version and commit identifier
- **THEN** the suite proceeds with the run

#### Scenario: A malformed event

- **WHEN** an event names an unknown channel, or has a malformed version or
  commit identifier
- **THEN** the suite refuses it and publishes nothing

### Requirement: Each environment publishes to its own ledger branch

The suite SHALL publish production results to the production ledger branch and
stage results to the stage ledger branch, and SHALL NOT write one
environment's results to the other's branch.

#### Scenario: A production result

- **WHEN** a result is recorded for the production environment
- **THEN** only the production ledger branch changes

#### Scenario: A stage result

- **WHEN** a result is recorded for the stage environment
- **THEN** only the stage ledger branch changes

### Requirement: A ledger branch holds source records and generated views

Each ledger branch SHALL hold, as source records, one result file per channel
and a deployed record, and, as generated views, a machine-readable ledger and a
human-readable ledger. The generated views SHALL be derived only from the source
records.

#### Scenario: The contents of a ledger branch

- **WHEN** a ledger branch has been published
- **THEN** it holds channels/<channel>.json for each recorded channel,
  deployed.json, ledger.json, and LEDGER.md

#### Scenario: Generated views match the records

- **WHEN** the generated views are regenerated from the branch's source records
- **THEN** they are identical to the published views

### Requirement: The deployed record is updated regardless of test outcome

Whenever a channel-released event is recorded, the deployed record SHALL name
the channel's deployed version and commit, whether the channel's tests pass,
fail, or error.

#### Scenario: Tests fail

- **WHEN** a recorded run has failed scenarios
- **THEN** the deployed record names the channel's new version

#### Scenario: The run errors

- **WHEN** a recorded run ends in error
- **THEN** the deployed record names the channel's new version and the channel's
  column is stale or shows the error

### Requirement: A channel record carries its provenance

A channel's result file SHALL carry the channel version and commit, the core
version, the suite version, the recording time, the run identifier, and the
verification state. For an artifact channel it SHALL also carry the release time
taken from the channel's release metadata.

#### Scenario: A recorded result

- **WHEN** a channel's result is published
- **THEN** its file carries the version, commit, core version, suite version,
  recording time, run identifier, and verification state

#### Scenario: An artifact channel's release time

- **WHEN** an artifact channel's result is published
- **THEN** its file carries the release time from the release metadata, not from
  the triggering event

### Requirement: Publishing regenerates the generated views from the records

Publishing SHALL write only the channel's own result and its entry in the
deployed record, then regenerate the generated views from all source records on
the branch. When the branch has moved on, it SHALL re-read the branch, re-apply
its own change, and regenerate, rather than replay an earlier commit.

#### Scenario: Two channels publish at the same time

- **WHEN** two channels publish to the same ledger branch at the same time
- **THEN** the branch converges to a ledger that contains both results

#### Scenario: The branch moved on during publishing

- **WHEN** a publication is rejected because the branch has changed
- **THEN** it re-reads the branch, re-applies its own change, regenerates, and
  publishes again

#### Scenario: Nothing would change

- **WHEN** publishing produces no difference from the branch
- **THEN** no new commit is made

### Requirement: An older channel version does not overwrite a newer result

The suite SHALL NOT replace a channel's recorded result with a result for an
older channel version. Versions SHALL be ordered by semantic version.

#### Scenario: An older version arrives late

- **WHEN** a result for an older channel version arrives after a newer one was
  recorded
- **THEN** the recorded result is unchanged and the older result is refused

#### Scenario: The same or a newer version

- **WHEN** a result for the same or a newer channel version arrives
- **THEN** it replaces the recorded result

### Requirement: A forced publication is marked

A publication requested with the force option SHALL bypass the version ordering
check and SHALL mark the channel's record as forced, naming the actor who
requested it.

#### Scenario: A rollback is forced

- **WHEN** a maintainer forces a result for an older channel version
- **THEN** it replaces the recorded result and the record is marked as forced by
  that maintainer

### Requirement: Publishing treats the channel's result as untrusted data

The stage that holds write access SHALL accept only allowed fields from a
channel's result, SHALL refuse a result that names a channel other than the one
being recorded, SHALL render text safely, and SHALL NOT execute code obtained
from the channel under test.

#### Scenario: Unexpected fields

- **WHEN** a channel's result contains fields outside the allowed set
- **THEN** those fields are not published

#### Scenario: A result for a different channel

- **WHEN** a channel's result names a channel other than the one being recorded
- **THEN** the publication is refused

#### Scenario: Text containing markup

- **WHEN** a channel's result contains text that would be interpreted as markup
- **THEN** it is rendered as plain text in the human-readable ledger

#### Scenario: Code from the channel under test

- **WHEN** a result is published
- **THEN** no code obtained from the channel under test has been executed in the
  stage that holds write access

### Requirement: A new suite version publishes a complete ledger

When a new suite version is published, the suite SHALL re-test every channel at
the version named in the deployed record, so that the resulting ledger names the
new suite version and contains a result for every deployed channel.

#### Scenario: The re-run completes

- **WHEN** the re-run after a new suite version completes
- **THEN** the ledger names the new suite version and every deployed channel's
  column is current
