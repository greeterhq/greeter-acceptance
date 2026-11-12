# frozen_string_literal: true

RSpec.describe 'CompositionRoot' do
  let(:root) { GreeterAcceptance::CompositionRoot }
  let(:cli_env) { { 'GREETER_CHANNEL' => 'cli', 'GREETER_CLI_CMD' => '/bin/echo' } }
  let(:http_env) { { 'GREETER_CHANNEL' => 'http', 'GREETER_BASE_URL' => 'http://127.0.0.1:1' } }

  describe '.build_driver' do
    it 'builds the cli driver for GREETER_CHANNEL=cli' do
      expect(root.build_driver(env: cli_env)).to be_a(GreeterAcceptance::Drivers::CliDriver)
    end

    it 'builds the http driver for GREETER_CHANNEL=http' do
      expect(root.build_driver(env: http_env)).to be_a(GreeterAcceptance::Drivers::HttpDriver)
    end

    it 'refuses an unset channel and names the variable' do
      expect { root.build_driver(env: {}) }
        .to raise_error(root::ConfigurationError, /GREETER_CHANNEL is not set/)
    end

    it 'refuses an empty channel' do
      expect { root.build_driver(env: { 'GREETER_CHANNEL' => '' }) }
        .to raise_error(root::ConfigurationError, /GREETER_CHANNEL is not set/)
    end

    it 'refuses an unknown channel and names it with the known channels' do
      expect { root.build_driver(env: { 'GREETER_CHANNEL' => 'web' }) }
        .to raise_error(root::ConfigurationError, /web.*cli, http/)
    end

    it 'refuses the http channel without a base URL' do
      expect { root.build_driver(env: { 'GREETER_CHANNEL' => 'http' }) }
        .to raise_error(root::ConfigurationError, /GREETER_BASE_URL is required/)
    end
  end

  describe '.build_observed_driver' do
    it 'wraps the driver in the observing decorator' do
      expect(root.build_observed_driver(env: http_env)).to be_a(GreeterAcceptance::Observed)
    end

    it 'still reports the wrapped channel' do
      expect(root.build_observed_driver(env: http_env).channel).to eq(:http)
    end
  end

  describe '.channels' do
    it 'lists every known channel' do
      expect(root.channels).to eq(%w[cli http])
    end
  end
end
