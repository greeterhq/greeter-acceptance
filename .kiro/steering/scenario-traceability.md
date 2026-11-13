---
inclusion: always
---
# Scenario traceability - greeter-acceptance (exception to the global rule)

This file overrides, for this repo only, the global testing-discipline rule
"Every OpenSpec scenario maps to exactly one Cucumber scenario tagged
@requirement-<capability>". Every other global testing rule still applies here.

- Channel-behaviour capabilities: `greeting`. A capability belongs here when it
  describes what a channel does through the GreeterDriver port. Add it to this
  list when you create it; every other capability is a tooling capability.
- Every scenario in a channel-behaviour capability maps to exactly one Cucumber
  scenario in features/, tagged @requirement-<requirement-slug> and
  @scenario-<scenario-slug>.
- Exception: a scenario stating that a channel without a capability records not
  applicable has no Cucumber scenario of its own. The capability-gated Cucumber
  scenario covers it when it runs on such a channel.
- Tooling capabilities (driver-contract, traceability, acceptance-gate,
  environment-targets, ledger-publication) are verified by RSpec examples under
  spec/, and driver-contract by spec/drivers/greeter_driver_contract.rb. They
  have no Cucumber scenarios.
