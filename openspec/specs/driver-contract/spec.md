# driver-contract Specification

## Purpose

Defines the substitutability contract every channel adapter must satisfy: the
GreeterDriver port surface, capability declaration, and the neutral behaviour
drivers must exhibit so step definitions never see a channel's idiom.

## Requirements

### Requirement: Every driver exposes the GreeterDriver port surface

Every channel adapter SHALL implement the GreeterDriver port so step
definitions can call it without knowing the channel. The port SHALL expose the
channel identity, its declared capabilities, a capability query, a greet
operation accepting an optional idempotency key, a count query, and the last
neutral error.

#### Scenario: A driver answers the port surface

- **WHEN** the driver contract examples run against any driver
- **THEN** the driver responds to channel, capabilities, the capability query,
  greet, the count query, and the last neutral error

### Requirement: A driver declares its capabilities honestly

Every driver SHALL declare the set of capabilities it supports, and the
capability query SHALL agree with that set. A driver SHALL NOT claim a
capability it cannot honour.

#### Scenario: The capability query agrees with the declared set

- **WHEN** a capability is queried on a driver
- **THEN** the query returns true exactly when that capability is in the
  driver's declared set

### Requirement: A driver translates its channel idiom to neutral outcomes

Every driver SHALL translate its channel's native result into a neutral
outcome, exposing greeted and invalid-name outcomes without leaking exit codes,
HTTP statuses, headers, or JSON to step definitions.

#### Scenario: A successful greeting maps to the neutral greeted outcome

- **WHEN** a valid name is greeted through any driver
- **THEN** the result carries the neutral greeted outcome and the channel's
  native idiom is not exposed to the caller

#### Scenario: An invalid name maps to the neutral invalid-name error

- **WHEN** an invalid name is greeted through any driver
- **THEN** the last neutral error is the invalid-name symbol and the channel's
  native idiom is not exposed to the caller

### Requirement: A driver reports an unobservable count neutrally

A driver whose channel cannot count SHALL report the count as unobservable
rather than raising or returning a misleading value, so the suite can record
the observation as not applicable.

#### Scenario: Count query on a channel without counting

- **WHEN** the count is queried on a driver that does not support counting
- **THEN** the driver reports the count as unobservable rather than a number
