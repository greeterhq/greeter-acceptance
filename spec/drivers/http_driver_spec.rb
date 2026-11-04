# frozen_string_literal: true

require_relative 'greeter_driver_contract'

RSpec.describe 'HttpDriver' do # rubocop:disable RSpec/DescribeClass
  subject(:driver) do
    GreeterAcceptance::Drivers::HttpDriver.new(
      base_url: ENV.fetch('GREETER_BASE_URL', 'http://localhost:3000')
    )
  end

  it_behaves_like 'a GreeterDriver'

  it 'declares counting and idempotency' do
    expect(driver.capabilities).to eq(Set[:counting, :idempotency])
  end
end
