Feature: Greeting a guest on any channel
  Every greeterHQ channel greets a valid guest and rejects an invalid name.
  Channels that can count greetings, or replay them idempotently, also honour
  the capability-gated scenarios below.

  @requirement-greeting-happy @scenario-greet-new-guest
  Scenario: Greeting a new guest
    Given a guest who has not been greeted before
    When I greet the guest
    Then the guest is greeted

  @requirement-greeting-invalid @scenario-reject-empty-name
  Scenario: Greeting with an empty name
    When I greet a guest with an empty name
    Then the greeting is rejected as invalid

  @requirement-greeting-count @scenario-count-new-guest @capability-counting
  Scenario: The greeting count is recorded for a new guest
    Given a guest who has not been greeted before
    When I greet the guest
    Then the greeting count for the guest is 1

  @requirement-greeting-returning @scenario-count-returning-guest @capability-counting
  Scenario: The greeting count increments for a returning guest
    Given a guest who has not been greeted before
    When I greet the guest
    And I greet the guest again
    Then the greeting count for the guest is 2

  @requirement-greeting-idempotent @scenario-idempotent-replay @capability-counting @capability-idempotency
  Scenario: An idempotent replay does not double-count
    Given a guest who has not been greeted before
    And an idempotency key
    When I greet the guest with that idempotency key
    And I greet the guest with the same idempotency key again
    Then the greeting count for the guest is 1
