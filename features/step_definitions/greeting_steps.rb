# frozen_string_literal: true

require 'securerandom'

# Steps talk to the GreeterDriver port only, via the `driver` the composition
# root (features/support/env.rb) provides. No exit codes, statuses, headers or
# JSON appear here.

Given('a guest who has not been greeted before') do
  @guest = "guest-#{SecureRandom.hex(4)}"
end

Given('an idempotency key') do
  @idempotency_key = "key-#{SecureRandom.hex(8)}"
end

When('I greet the guest( again)') do
  @result = driver.greet(@guest)
end

When(/^I greet the guest with (?:that|the same) idempotency key(?: again)?$/) do
  @result = driver.greet(@guest, idempotency_key: @idempotency_key)
end

When('I greet a guest with an empty name') do
  @result = driver.greet('')
end

Then('the guest is greeted') do
  expect(@result.outcome).to eq(:greeted)
  expect(@result.guest_name).to eq(@guest)
end

Then('the greeting is rejected as invalid') do
  expect(driver.last_error).to eq(:invalid_name)
end

Then('the greeting count for the guest is {int}') do |expected|
  expect(driver.count_for(@guest)).to eq(expected)
end
