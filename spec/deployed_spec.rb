# frozen_string_literal: true

RSpec.describe 'Deployed' do
  let(:deployed) { GreeterAcceptance::Deployed }
  let(:cli_entry) { { version: 'v0.1.2', sha: 'abc1234', artifact: 'tag', run_id: '812' } }
  let(:http_entry) { { version: 'v1.2.3', sha: 'def4567', run_id: '815' } }

  def update(document, channel, entry)
    deployed.update(document, channel: channel, **entry)
  end

  describe '.empty' do
    it 'is an empty greeterhq.deployed.v1 document for the environment' do
      expect(deployed.empty(environment: 'prod')).to eq(
        'schema' => 'greeterhq.deployed.v1', 'environment' => 'prod', 'channels' => {}
      )
    end
  end

  describe '.update' do
    it 'adds only the named channel entry' do
      document = update(deployed.empty(environment: 'prod'), 'cli', cli_entry)

      expect(document['channels']).to eq(
        'cli' => { 'version' => 'v0.1.2', 'sha' => 'abc1234', 'artifact' => 'tag', 'run_id' => '812' }
      )
    end

    it 'leaves every other channel entry as it was' do
      first = update(deployed.empty(environment: 'prod'), 'cli', cli_entry)
      second = update(first, 'http', http_entry)

      expect(second['channels']['cli']).to eq(first['channels']['cli'])
      expect(second['channels'].keys).to contain_exactly('cli', 'http')
    end

    it 'replaces the entry of a channel that is already recorded' do
      first = update(deployed.empty(environment: 'prod'), 'http', http_entry)
      second = update(first, 'http', http_entry.merge(version: 'v1.2.4'))

      expect(second['channels']['http']['version']).to eq('v1.2.4')
    end

    it 'omits the artifact for a channel that has none' do
      document = update(deployed.empty(environment: 'prod'), 'http', http_entry)

      expect(document['channels']['http']).not_to have_key('artifact')
    end

    it 'does not modify the document it is given' do
      original = deployed.empty(environment: 'prod')
      update(original, 'cli', cli_entry)

      expect(original['channels']).to eq({})
    end
  end
end
