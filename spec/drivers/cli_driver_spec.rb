# frozen_string_literal: true

require_relative 'greeter_driver_contract'

RSpec.describe 'CliDriver' do
  subject(:driver) do
    GreeterAcceptance::Drivers::CliDriver.new(
      command: ENV.fetch('GREETER_CLI_CMD', 'greeter'),
      chdir: ENV.fetch('GREETER_CLI_DIR', nil)
    )
  end

  it_behaves_like 'a GreeterDriver'

  describe 'when the greeter command cannot be run' do
    let(:unreachable_driver) do
      GreeterAcceptance::Drivers::CliDriver.new(command: '/nonexistent/greeter')
    end

    it_behaves_like 'a driver whose channel is unreachable'
  end

  it 'declares no capabilities' do
    expect(driver.capabilities).to eq(Set.new)
  end
end
