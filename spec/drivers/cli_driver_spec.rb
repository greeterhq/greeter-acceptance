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

  it 'declares no capabilities' do
    expect(driver.capabilities).to eq(Set.new)
  end
end
