# greeting Specification

## Purpose

Defines the channel-neutral greeting behaviour every greeterHQ channel shares,
exercised through the GreeterDriver port, including the capability-gated
observations that distinguish channels from one another.

## Requirements

### Requirement: A channel greets a valid guest

Any channel SHALL greet a guest when given a valid name, regardless of the
channel's idiom. The greeting is the universal behaviour every channel must
honour.

#### Scenario: Greeting a new guest

- **WHEN** a valid name is greeted on any channel
- **THEN** the guest is greeted

### Requirement: A channel rejects an invalid name

Any channel SHALL reject a greeting request whose name is invalid, surfacing a
neutral invalid-name outcome rather than greeting the guest.

#### Scenario: Greeting with an empty name

- **WHEN** an empty name is greeted on any channel
- **THEN** the greeting is rejected as invalid

### Requirement: A counting channel records the greeting count

A channel that supports counting SHALL report how many times a guest has been
greeted. A channel without counting records this observation as not applicable
rather than failing.

#### Scenario: Count after a first greeting on a counting channel

- **WHEN** a valid name is greeted once on a channel with counting
- **THEN** the greeting count for that guest is 1

#### Scenario: Channel without counting records not applicable

- **WHEN** this behaviour runs on a channel without counting
- **THEN** the scenario is recorded as not applicable, never failed

### Requirement: A counting channel increments the count for a returning guest

A channel that supports counting SHALL increment a guest's greeting count each
time the same guest is greeted again. A channel without counting records this
observation as not applicable.

#### Scenario: Count after a returning-guest greeting on a counting channel

- **WHEN** the same valid name is greeted twice on a channel with counting
- **THEN** the greeting count for that guest is 2

### Requirement: An idempotent replay does not double-count

A channel that supports counting and idempotency SHALL treat a replayed
greeting carrying the same idempotency key as a single greeting, leaving the
count unchanged by the replay. A channel lacking either capability records this
observation as not applicable.

#### Scenario: Replaying the same idempotency key on a capable channel

- **WHEN** the same valid name is greeted twice with the same idempotency key on
  a channel with counting and idempotency
- **THEN** the greeting count for that guest is 1
