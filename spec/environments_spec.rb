# frozen_string_literal: true

require 'tmpdir'
require 'yaml'

RSpec.describe 'Environments' do
  let(:environments) { GreeterAcceptance::Environments }
  let(:config) { environments.new(environments_config) }

  describe '#resolve' do
    it 'resolves an http target from the committed configuration' do
      target = config.resolve(environment: 'prod', channel: 'http')

      expect(target.base_url).to eq('https://prodapi1.execute-api.eu-west-2.amazonaws.com')
    end

    it 'resolves a cli target to its release repository' do
      expect(config.resolve(environment: 'prod', channel: 'cli').repo).to eq('greeterhq/greeter-cli')
    end

    it 'refuses a request that carries a target address, before anything else' do
      expect { config.resolve(environment: 'prod', channel: 'http', requested_address: 'https://evil.test') }
        .to raise_error(environments::Refused, /address/)
    end

    it 'refuses a target whose host does not match the environment pattern' do
      bad = environments_config
      bad['environments']['prod']['channels']['http']['base_url'] = 'https://evil.example.com'

      expect { environments.new(bad).resolve(environment: 'prod', channel: 'http') }
        .to raise_error(environments::Refused, /host.*prod|prod.*host/)
    end

    it 'refuses an unknown environment and names it' do
      expect { config.resolve(environment: 'dev', channel: 'http') }
        .to raise_error(environments::Refused, /unknown environment 'dev'/)
    end

    it 'refuses a channel with no target in the environment and names it' do
      expect { config.resolve(environment: 'stage', channel: 'cli') }
        .to raise_error(environments::Refused, /no target for channel 'cli' in environment 'stage'/)
    end
  end

  describe 'lookups' do
    it 'returns the ledger branch of an environment' do
      expect(config.ledger_branch('stage')).to eq('ledger-stage')
    end

    it 'lists the environments and the channels of each' do
      expect(config.environments).to contain_exactly('prod', 'stage')
      expect(config.channels_for('prod')).to contain_exactly('http', 'cli')
    end
  end

  describe '.load' do
    it 'reads the configuration from a YAML file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'environments.yml')
        File.write(path, environments_config.to_yaml)

        expect(environments.load(path).ledger_branch('prod')).to eq('ledger-prod')
      end
    end
  end

  describe 'the committed config/environments.yml' do
    let(:committed) { environments.load(File.expand_path('../config/environments.yml', __dir__)) }

    it 'defines prod and stage' do
      expect(committed.environments).to include('prod', 'stage')
    end

    it 'resolves every channel of every environment, so each host matches its pattern' do
      committed.environments.each do |environment|
        committed.channels_for(environment).each do |channel|
          expect { committed.resolve(environment: environment, channel: channel) }.not_to raise_error
        end
      end
    end
  end
end
