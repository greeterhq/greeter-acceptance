# Spec Delta

## ADDED Requirements

### Requirement: A record run installs an artifact channel's release exactly as locked

A record run SHALL install an artifact channel's release only from the lockfile
the release ships. When that lockfile is missing or does not match the release's
declared dependencies, the run SHALL fail before running any scenario. It SHALL
NOT resolve dependencies afresh. The deployment is still recorded, as for any
run that produced no result.

#### Scenario: A release with a matching lockfile

- **WHEN** a release ships a lockfile that matches its declared dependencies
- **THEN** the record run installs exactly the dependency versions the lockfile
  pins

#### Scenario: A release whose lockfile is missing or out of date

- **WHEN** a release ships no lockfile, or one that does not match its declared
  dependencies
- **THEN** the record run fails before running any scenario, says why, and the
  deployed record is still updated

### Requirement: No credential is reachable after candidate code has run in a record run

In a record run's test stage, every step that holds a token or secret SHALL run
before the first step that executes code obtained from the channel under test.

#### Scenario: Looking up a release's publish time

- **WHEN** a record run needs the publish time of an artifact channel's release
- **THEN** it looks it up before the release is downloaded, and no step after
  the release's install references a token or a secret
