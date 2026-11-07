# frozen_string_literal: true

RSpec.describe 'Resolver' do
  let(:resolver_class) { GreeterAcceptance::Resolver }
  let(:environments) { GreeterAcceptance::Environments.new(environments_config) }
  let(:resolver) { resolver_class.new(environments: environments) }
  let(:payload) do
    { 'channel' => 'cli', 'version' => 'v0.1.2', 'sha' => 'abc1234', 'artifact' => 'tag', 'environment' => 'prod' }
  end
  let(:deployed) do
    {
      'prod' => deployed_doc(
        cli: { version: 'v0.1.2', sha: 'abc1234', artifact: 'tag' }, http: { version: 'v1.2.3', sha: 'def4567' }
      ),
      'stage' => deployed_doc(environment: 'stage', http: { version: 'v1.3.0', sha: '1234567' })
    }
  end

  describe 'a channel-released event' do
    it 'yields a matrix of exactly that channel' do
      matrix = resolver.matrix(trigger: :channel_released, payload: payload)

      expect(matrix.length).to eq(1)
      expect(matrix.first).to include('channel' => 'cli', 'version' => 'v0.1.2', 'environment' => 'prod')
    end

    it 'adds the ledger branch of the environment from the committed configuration' do
      matrix = resolver.matrix(trigger: :channel_released, payload: payload)

      expect(matrix.first['ledger_branch']).to eq('ledger-prod')
    end

    it 'refuses an invalid event and yields nothing' do
      expect { resolver.matrix(trigger: :channel_released, payload: payload.merge('channel' => 'web')) }
        .to raise_error(GreeterAcceptance::EventValidation::Invalid)
    end
  end

  describe 'a new suite version' do
    it 'yields every channel named in the deployed record of every environment' do
      matrix = resolver.matrix(trigger: :suite_tag, deployed: deployed)

      expect(matrix.map { |entry| entry.values_at('environment', 'channel') })
        .to contain_exactly(%w[prod cli], %w[prod http], %w[stage http])
    end

    it 'tests each channel at the version in the deployed record' do
      matrix = resolver.matrix(trigger: :suite_tag, deployed: deployed)
      http = matrix.find { |entry| entry.values_at('environment', 'channel') == %w[prod http] }

      expect(http).to include('version' => 'v1.2.3', 'sha' => 'def4567', 'ledger_branch' => 'ledger-prod')
    end
  end

  describe 'a manual run' do
    it 'behaves as the event would when given the event fields' do
      expect(resolver.matrix(trigger: :manual, payload: payload))
        .to eq(resolver.matrix(trigger: :channel_released, payload: payload))
    end

    it 'yields every deployed channel when asked to re-run everything' do
      matrix = resolver.matrix(trigger: :manual, deployed: deployed, rerun_all: true)

      expect(matrix.length).to eq(3)
    end
  end

  describe '.latest_suite_tag' do
    it 'chooses the highest released version by number, not alphabetically' do
      tags = %w[v0.1.0 v0.2.0 v0.10.0 v0.3.0-rc1 main nightly]

      expect(resolver_class.latest_suite_tag(tags)).to eq('v0.10.0')
    end

    it 'is nil when no version has been released' do
      expect(resolver_class.latest_suite_tag(%w[main nightly])).to be_nil
    end
  end
end
