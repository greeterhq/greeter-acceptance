# Spec Delta

## MODIFIED Requirements

### Requirement: Each run writes neutral per-channel traceability rows

Every run SHALL write a traceability artifact for the channel under test,
containing one row per scenario with its requirement, scenario identity, and
status of passed, failed, error, or not applicable. A not-applicable row SHALL
record the missing capabilities that caused it. The artifact SHALL also record
the run context: suite version, channel version, core version, environment,
recording time, and run identifier.

#### Scenario: A run records one status per scenario

- **WHEN** the suite runs against a single channel
- **THEN** the traceability artifact contains one row per scenario with a status
  of passed, failed, error, or not applicable

#### Scenario: A not-applicable row names its missing capabilities

- **WHEN** a scenario is recorded as not applicable for the channel
- **THEN** its row lists the capabilities the channel lacked

#### Scenario: A run records its context

- **WHEN** the suite runs against a channel
- **THEN** the artifact records the suite version, the observed channel version
  and core version, the environment, the recording time, and the run identifier

### Requirement: The suite derives a cross-channel ledger

The suite SHALL derive a ledger that merges the per-channel traceability
artifacts into a requirement-by-channel matrix, giving each requirement a
status for every known channel. The ledger is the published view of the
capability frontier.

#### Scenario: Merging two channel runs into the ledger

- **WHEN** the per-channel artifacts for two channels are merged
- **THEN** the ledger lists each requirement with its status for each channel

#### Scenario: A known channel with no result

- **WHEN** the artifacts are merged and a known channel has no artifact
- **THEN** the ledger still lists that channel, with every requirement missing

## ADDED Requirements

### Requirement: A scenario hit by an infrastructure error is recorded as error

When the channel under test reports an infrastructure error during a scenario,
the suite SHALL record that scenario as error, not failed or passed. An error
SHALL replace a previously recorded passed result in the same way a failure
does.

#### Scenario: A channel failure during a scenario

- **WHEN** the channel reports an infrastructure error while a scenario runs
- **THEN** the scenario is recorded as error

#### Scenario: A failed assertion is not an error

- **WHEN** a scenario's assertion fails and the channel reported no
  infrastructure error
- **THEN** the scenario is recorded as failed

#### Scenario: An error replaces an earlier pass

- **WHEN** a channel's new result contains an error for a requirement that its
  previous result recorded as passed
- **THEN** the ledger shows error for that requirement

### Requirement: A run is attributed to one verified channel version

The suite SHALL compare the build information observed during a run with the
version the run was expected to test, and record the run as verified,
mismatched, inconsistent, or unobserved. Results from a mismatched or
inconsistent run SHALL NOT be attributed to the expected version.

#### Scenario: Observed version matches the expectation

- **WHEN** every observation during a run equals the expected version
- **THEN** the run is recorded as verified

#### Scenario: Observed version differs from the expectation

- **WHEN** the observed version differs from the expected version
- **THEN** the run is recorded as mismatched and its results are not attributed
  to the expected version

#### Scenario: The version changes during a run

- **WHEN** two observations during one run report different versions
- **THEN** the run is recorded as inconsistent

#### Scenario: No version is observed

- **WHEN** no observation is available during a run
- **THEN** the run is recorded as unobserved

### Requirement: A ledger cell is missing when no row exists

A ledger cell SHALL read missing, not not applicable, when a channel has no row
for a requirement. Not applicable is reserved for a channel's declared
capabilities.

#### Scenario: A requirement with no row

- **WHEN** a channel's result has no row for a requirement the suite defines
- **THEN** the ledger cell for that channel and requirement reads missing

#### Scenario: A requirement the channel cannot honour

- **WHEN** a channel's row for a requirement is not applicable
- **THEN** the ledger cell reads not applicable

### Requirement: A ledger column is current, stale, or missing

A channel's ledger column SHALL be current when its result was produced by the
ledger's suite version for the channel version now deployed, stale when it was
produced by an older suite version or for a version no longer deployed, and
missing when the channel has no result. A stale column SHALL show its last known
statuses marked as stale.

#### Scenario: A result for the deployed version and current suite

- **WHEN** a channel's result was produced by the ledger's suite version for the
  version recorded as deployed
- **THEN** the channel's column is current

#### Scenario: A result from an older suite version

- **WHEN** a channel's result was produced by an older suite version
- **THEN** the column is stale and its statuses are marked as stale

#### Scenario: A newer version is deployed than the result covers

- **WHEN** the deployed record names a newer channel version than the result
- **THEN** the column is stale

#### Scenario: A known channel with no result

- **WHEN** a known channel has no result
- **THEN** the column is missing

### Requirement: Ledger generation is deterministic

The ledger and its human-readable rendering SHALL be a pure function of the
channel results, the deployed record, and the suite version, so that
regenerating from the same inputs yields identical output.

#### Scenario: Regenerating from the same inputs

- **WHEN** the ledger is generated twice from the same inputs
- **THEN** both outputs are identical

#### Scenario: Input order does not matter

- **WHEN** the same channel results are supplied in a different order
- **THEN** the generated ledger is identical
