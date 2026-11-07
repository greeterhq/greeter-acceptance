# frozen_string_literal: true

require_relative 'greeter_driver_contract'

RSpec.describe 'HttpDriver' do
  subject(:driver) do
    GreeterAcceptance::Drivers::HttpDriver.new(
      base_url: ENV.fetch('GREETER_BASE_URL', 'http://localhost:3000')
    )
  end

  it_behaves_like 'a GreeterDriver'

  describe 'when the service cannot be reached' do
    let(:unreachable_driver) do
      GreeterAcceptance::Drivers::HttpDriver.new(base_url: 'http://127.0.0.1:1')
    end

    it_behaves_like 'a driver whose channel is unreachable'
  end

  it 'declares counting and idempotency' do
    expect(driver.capabilities).to eq(Set[:counting, :idempotency])
  end
end
