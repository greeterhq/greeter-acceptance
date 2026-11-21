# frozen_string_literal: true

# Test-only helpers.
Dir[File.expand_path('support/**/*.rb', __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.include LedgerFixtures
end
