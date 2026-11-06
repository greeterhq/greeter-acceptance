# traceability Specification

## Purpose

Defines the run artifacts the suite produces: per-channel traceability rows and
the derived cross-channel ledger that shows which channel honours which
requirement and where capabilities differ.

## Requirements

### Requirement: A scenario is gated by its capability tags

The suite SHALL run a scenario only when the active channel supports every
capability the scenario requires. When a required capability is missing, the
entire scenario is recorded as not applicable, never failed or skipped.

#### Scenario: A capability-tagged scenario on a channel without the capability

- **WHEN** a scenario requiring a capability runs on a channel that lacks it
- **THEN** the scenario is recorded as not applicable with its missing
  capabilities, and none of its steps run

#### Scenario: A capability-tagged scenario on a channel with the capability

- **WHEN** a scenario requiring a capability runs on a channel that supports it
- **THEN** the scenario runs normally and is recorded as passed or failed

### Requirement: Every capability tag names a known capability

The suite SHALL verify that every capability tag used by a scenario names a
capability the suite knows, failing fast when a tag does not, so a mistyped tag
cannot silently cause a scenario to run and fail.

#### Scenario: An unknown capability tag halts the run

- **WHEN** a scenario is tagged with a capability name the suite does not know
- **THEN** the run fails fast and names the offending tag

### Requirement: Each run writes neutral per-channel traceability rows

Every run SHALL write a traceability artifact for the channel under test,
containing one row per scenario with its requirement, scenario identity, and
status of passed, failed, or not applicable. A not-applicable row SHALL record
the missing capabilities that caused it.

#### Scenario: A run records one status per scenario

- **WHEN** the suite runs against a single channel
- **THEN** the traceability artifact contains one row per scenario with a status
  of passed, failed, or not applicable

#### Scenario: A not-applicable row names its missing capabilities

- **WHEN** a scenario is recorded as not applicable for the channel
- **THEN** its row lists the capabilities the channel lacked

### Requirement: The suite derives a cross-channel ledger

The suite SHALL derive a ledger that merges the per-channel traceability
artifacts into a requirement-by-channel matrix, giving each requirement a status
for every channel that ran. The ledger is the published view of the capability
frontier.

#### Scenario: Merging two channel runs into the ledger

- **WHEN** the per-channel artifacts for two channels are merged
- **THEN** the ledger lists each requirement with its status for each channel
