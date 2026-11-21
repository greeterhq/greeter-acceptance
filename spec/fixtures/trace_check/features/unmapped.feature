Feature: Fixture scenario with a tag outside the map

  @requirement-beta-mapped @scenario-whatever
  Scenario: A mapped scenario
    Given a fixture

  @requirement-greeting-unmapped @scenario-whatever
  Scenario: An unmapped scenario
    Given a fixture
