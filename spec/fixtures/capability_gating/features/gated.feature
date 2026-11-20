Feature: Capability gating fixtures

  @requirement-fixture-gated @scenario-fixture-gated @capability-counting
  Scenario: A scenario that needs counting
    Given the gated scenario runs

  @requirement-fixture-plain @scenario-fixture-plain
  Scenario: A scenario that needs nothing
    Given the plain scenario runs
