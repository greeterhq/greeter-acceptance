# Spec Delta

## ADDED Requirements

### Requirement: An artifact channel's candidate is installed exactly as locked

The gate SHALL install an artifact channel's candidate only from the lockfile
the candidate ships, and SHALL fail before running any scenario when that
lockfile is missing or does not match the candidate's declared dependencies. It
SHALL NOT resolve dependencies afresh.

#### Scenario: A candidate with a matching lockfile

- **WHEN** a candidate ships a lockfile that matches its declared dependencies
- **THEN** the gate installs exactly the dependency versions the lockfile pins

#### Scenario: A candidate without a lockfile

- **WHEN** a candidate ships no lockfile
- **THEN** the gate fails before running any scenario and says a lockfile is
  required

#### Scenario: A candidate whose lockfile is out of date

- **WHEN** a candidate's lockfile does not match its declared dependencies
- **THEN** the gate fails before running any scenario and says the lockfile
  does not match

### Requirement: No credential is reachable after candidate code has run in the gate

In a gate run, no step that holds a token or secret SHALL run after the first
step that executes code obtained from the candidate.

#### Scenario: Steps after the candidate's install

- **WHEN** the gate's steps are inspected
- **THEN** no step after the one that installs the candidate references a token
  or a secret
