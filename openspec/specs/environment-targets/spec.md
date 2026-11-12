# environment-targets Specification

## Purpose

Defines how the suite decides which endpoint a channel run targets, so that a
target always comes from reviewed, committed configuration and never from an
event, an input, or a caller.

## Requirements

### Requirement: Targets are read from committed configuration

The suite SHALL resolve a channel's target for a named environment from the
configuration committed on the default branch. It SHALL NOT accept a target
address from a dispatch payload, a workflow input, or any other caller-supplied
value.

#### Scenario: An environment resolves to its configured target

- **WHEN** a run names a known environment and channel
- **THEN** the target is the one in the committed configuration for that
  environment and channel

#### Scenario: A supplied target address is refused

- **WHEN** a run request carries a target address
- **THEN** the run is refused before any request is made to a channel

### Requirement: A target host must match its environment's allowed pattern

Before making any request, the suite SHALL check the resolved target's host
against the allowed host pattern configured for that environment, and SHALL
refuse to run when it does not match.

#### Scenario: A host that matches the pattern

- **WHEN** the resolved target's host matches the environment's allowed pattern
- **THEN** the run proceeds

#### Scenario: A host that does not match the pattern

- **WHEN** the resolved target's host does not match the environment's allowed
  pattern
- **THEN** the run is refused before any request is made

### Requirement: Unknown environments and channels are refused

The suite SHALL refuse a run that names an environment, or a channel within an
environment, that the committed configuration does not define.

#### Scenario: An unknown environment

- **WHEN** a run names an environment that is not configured
- **THEN** the run is refused and the unknown environment is named

#### Scenario: A channel with no target in the environment

- **WHEN** a run names a channel that has no target in the named environment
- **THEN** the run is refused and the missing channel is named
