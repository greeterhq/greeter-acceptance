# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Load everything under lib/ so that adding a library file never needs an edit
# to this helper. Files are required relative to one another where they depend
# on each other, so the sorted order is safe.
Dir[File.expand_path('../lib/**/*.rb', __dir__)].each { |file| require file }

# Test-only helpers. These deliberately do not depend on lib/, so a missing
# class in lib/ fails the example that uses it rather than the fixture.
Dir[File.expand_path('support/**/*.rb', __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.include LedgerFixtures
  config.include GitHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
