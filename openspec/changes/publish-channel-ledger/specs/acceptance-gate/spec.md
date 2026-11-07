# Spec Delta

## Purpose

Defines the read-only gate that a channel's release pipeline calls to prove a
candidate release passes the channel-neutral suite before it is published or
promoted, using the suite version the channel has pinned.

## ADDED Requirements

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
