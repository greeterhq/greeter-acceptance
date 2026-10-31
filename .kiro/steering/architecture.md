---
inclusion: always
---
# Hexagonal tests - greeter-acceptance
- lib/greeter_acceptance/ports/greeter_driver.rb   the ONLY interface steps may call
- lib/greeter_acceptance/drivers/*_driver.rb        one adapter per channel
- features/support/env.rb                            the ONLY composition root;
  picks the driver from ENV['GREETER_CHANNEL'] (cli|http)
- Drivers are black-box. Never require greeter-core, greeter-cli or greeter-http code.
- Step definitions never mention exit codes, HTTP statuses or JSON. Those live in drivers.
- Every driver passes spec/drivers/greeter_driver_contract.rb.
