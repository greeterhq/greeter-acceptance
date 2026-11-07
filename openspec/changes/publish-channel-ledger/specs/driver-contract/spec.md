# Spec Delta

## MODIFIED Requirements

### Requirement: Every driver exposes the GreeterDriver port surface

Every channel adapter SHALL implement the GreeterDriver port so step
definitions can call it without knowing the channel. The port SHALL expose the
channel identity, its declared capabilities, a capability query, a greet
operation accepting an optional idempotency key, a count query, the last
neutral error, and the build information of the channel under test.

#### Scenario: A driver answers the port surface

- **WHEN** the driver contract examples run against any driver
- **THEN** the driver responds to channel, capabilities, the capability query,
  greet, the count query, the last neutral error, and build information

### Requirement: A driver translates its channel idiom to neutral outcomes

Every driver SHALL translate its channel's native result into a neutral
outcome (greeted, invalid name, or infrastructure error) without leaking exit
codes, HTTP statuses, headers, or JSON to step definitions. A driver SHALL
return an infrastructure error, not raise, when its channel cannot be reached
or fails unexpectedly.

#### Scenario: A successful greeting maps to the neutral greeted outcome

- **WHEN** a valid name is greeted through any driver
- **THEN** the result carries the neutral greeted outcome and the channel's
  native idiom is not exposed to the caller

#### Scenario: An invalid name maps to the neutral invalid-name error

- **WHEN** an invalid name is greeted through any driver
- **THEN** the last neutral error is the invalid-name symbol and the channel's
  native idiom is not exposed to the caller

#### Scenario: A failing channel maps to the neutral infrastructure error

- **WHEN** a valid name is greeted through any driver and the channel cannot be
  reached or fails unexpectedly
- **THEN** the result carries the neutral infrastructure-error outcome, the last
  neutral error is the infrastructure-error symbol, and no native error is
  raised to the caller

## ADDED Requirements

### Requirement: A driver reports the build information of its channel

Every driver SHALL report the channel version and the core version of the
channel under test, or report that they are unobservable. Reporting SHALL NOT
change the channel's observable state.

#### Scenario: A channel that reports its versions

- **WHEN** build information is requested from a driver whose channel reports
  its versions
- **THEN** the channel version and the core version are returned

#### Scenario: A channel that does not report its versions

- **WHEN** build information is requested from a driver whose channel does not
  report its versions
- **THEN** the driver reports the build information as unobservable rather than
  returning a guessed value

#### Scenario: Reporting leaves the channel unchanged

- **WHEN** build information is requested from any driver
- **THEN** no guest is greeted and no count changes
