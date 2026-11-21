# beta Specification

## Purpose

A fixture channel-behaviour capability: its requirements are verified by Cucumber
scenarios, matched through a tag map.

## Requirements

### Requirement: A mapped requirement

A Cucumber scenario SHALL carry its mapped tag.

#### Scenario: A mapped scenario

- **WHEN** it is checked
- **THEN** the mapped tag is found

### Requirement: A mapped requirement with no scenario

No Cucumber scenario SHALL carry its mapped tag.

#### Scenario: A missing scenario

- **WHEN** it is checked
- **THEN** it is reported
