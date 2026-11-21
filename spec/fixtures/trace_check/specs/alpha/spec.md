# alpha Specification

## Purpose

A fixture tooling capability for the trace-check specs.

## Requirements

### Requirement: Covered requirement

The fixture SHALL have a tagged example.

#### Scenario: Covered scenario

- **WHEN** it is checked
- **THEN** it is covered

### Requirement: Uncovered requirement

The fixture SHALL have no tagged example.

#### Scenario: Uncovered scenario

- **WHEN** it is checked
- **THEN** it is reported

### Requirement: Same text

Its scenario repeats the requirement text.

#### Scenario: Same text

- **WHEN** it is checked
- **THEN** the scenario slug equals the requirement slug
