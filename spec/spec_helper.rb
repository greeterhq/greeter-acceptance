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

  # add-pact-consumer: the Pact consumer specs run only on request
  # (`bundle exec rspec -t pact spec/pact/providers`). Excluded here, not only by
  # the pact gem, so the default run skips any :pact example even when the gem
  # is not loaded. Selecting the tag with -t lifts this exclusion.
  config.filter_run_excluding :pact
end
