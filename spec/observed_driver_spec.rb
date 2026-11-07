# frozen_string_literal: true

RSpec.describe 'Observed' do
  let(:greeted) do
    GreeterAcceptance::Ports::GreetResult.new(
      message: 'Hello, Ada!', guest_name: 'Ada', count: 1, outcome: :greeted
    )
  end
  let(:broken) do
    GreeterAcceptance::Ports::GreetResult.new(
      message: nil, guest_name: 'Ada', count: nil, outcome: :infrastructure_error
    )
  end
  let(:info) do
    GreeterAcceptance::Ports::BuildInfo.new(channel_version: 'v1.2.3', core_version: '0.1.5')
  end
  let(:results) { [greeted] }
  let(:inner) { ScriptedDriver.new(results: results, build_info: info) }
  let(:observed) { GreeterAcceptance::Observed.new(inner) }

  describe 'forwarding' do
    it 'forwards the read-only port methods to the wrapped driver' do
      expect(observed.channel).to eq(:http)
      expect(observed.supports?(:counting)).to be(true)
      expect(observed.count_for('Ada')).to eq(7)
    end

    it 'forwards the error accessors to the wrapped driver' do
      expect(observed.last_native_error).to eq('native')
      expect(observed.native_idiom_for?(:invalid_name)).to be(false)
    end

    it 'passes the greeting and idempotency key through and returns the result unchanged' do
      result = observed.greet('Ada', idempotency_key: 'key-1')

      expect(result).to equal(greeted)
      expect(inner.greets).to eq([%w[Ada key-1]])
    end
  end

  describe '#infrastructure_error?' do
    it 'is false before anything has been greeted' do
      expect(observed.infrastructure_error?).to be(false)
    end

    it 'is false when every greeting succeeded' do
      observed.greet('Ada')

      expect(observed.infrastructure_error?).to be(false)
    end

    context 'when a greeting hits an infrastructure error and a later one succeeds' do
      let(:results) { [broken, greeted] }

      before do
        observed.greet('Ada')
        observed.greet('Ada')
      end

      it 'stays true for the rest of the scenario' do
        expect(observed.infrastructure_error?).to be(true)
      end

      it 'is not undone by the wrapped driver clearing its own last error' do
        expect(observed.last_error).to be_nil
      end
    end
  end

  describe '#build_info' do
    it 'returns the wrapped driver build information and remembers it' do
      expect(observed.build_info).to eq(info)
      expect(observed.build_infos).to eq([info])
    end

    it 'remembers each distinct build information once' do
      2.times { observed.build_info }

      expect(observed.build_infos).to eq([info])
    end

    it 'does not remember an unobservable build information' do
      silent = GreeterAcceptance::Observed.new(ScriptedDriver.new(build_info: nil))

      expect(silent.build_info).to be_nil
      expect(silent.build_infos).to eq([])
    end
  end
end
