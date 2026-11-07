# frozen_string_literal: true

require 'securerandom'

# Shared contract every GreeterDriver adapter must satisfy.
# Including context must define `driver`.
RSpec.shared_examples 'a GreeterDriver' do
  let(:guest) { "guest-#{SecureRandom.hex(4)}" }

  describe 'port surface' do
    %i[
      channel capabilities supports? greet count_for
      last_error last_native_error native_idiom_for? build_info
    ].each do |method_name|
      it "responds to #{method_name}" do
        expect(driver).to respond_to(method_name)
      end
    end
  end

  describe 'capability declaration' do
    it 'declares its capabilities as a set of symbols' do
      expect(driver.capabilities).to be_a(Set)
      expect(driver.capabilities).to all(be_a(Symbol))
    end

    it 'answers supports? exactly for the declared capabilities' do
      %i[counting idempotency].each do |capability|
        expect(driver.supports?(capability))
          .to eq(driver.capabilities.include?(capability))
      end
    end
  end

  describe 'neutral outcomes' do
    it 'maps a valid greeting to the neutral greeted outcome' do
      result = driver.greet(guest)

      expect(result.outcome).to eq(:greeted)
      expect(result.guest_name).to eq(guest)
    end

    it 'does not expose channel idiom on the greet result' do
      result = driver.greet(guest)

      expect(result.members).to contain_exactly(:message, :guest_name, :count, :outcome)
    end

    it 'maps an invalid name to the neutral invalid_name error' do
      driver.greet('')

      expect(driver.last_error).to eq(:invalid_name)
    end
  end

  describe 'count observability' do
    it 'reports :not_applicable when counting is unsupported' do
      skip 'driver supports counting' if driver.supports?(:counting)

      expect(driver.count_for(guest)).to eq(:not_applicable)
    end

    it 'reports an Integer count when counting is supported' do
      skip 'driver does not support counting' unless driver.supports?(:counting)

      driver.greet(guest)

      expect(driver.count_for(guest)).to eq(1)
    end
  end

  describe 'build information' do
    it 'reports channel and core versions, or nil when the channel does not report them' do
      expect(driver.build_info).to be_nil.or(respond_to(:channel_version, :core_version))
    end

    it 'changes no count when it is requested' do
      skip 'driver does not support counting' unless driver.supports?(:counting)

      driver.greet(guest)
      driver.build_info

      expect(driver.count_for(guest)).to eq(1)
    end
  end
end

# Shared contract for a driver whose channel cannot be reached. Including
# context must define `unreachable_driver`.
RSpec.shared_examples 'a driver whose channel is unreachable' do
  it 'returns the infrastructure_error outcome instead of raising' do
    result = nil

    expect { result = unreachable_driver.greet('Ada') }.not_to raise_error
    expect(result.outcome).to eq(:infrastructure_error)
  end

  it 'exposes infrastructure_error as the last neutral error' do
    unreachable_driver.greet('Ada')

    expect(unreachable_driver.last_error).to eq(:infrastructure_error)
  end
end
