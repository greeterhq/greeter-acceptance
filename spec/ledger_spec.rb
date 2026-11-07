# frozen_string_literal: true

require 'json'
require 'tmpdir'

RSpec.describe 'Ledger v2' do
  let(:ledger_class) { GreeterAcceptance::Ledger }
  let(:requirements) { %w[greeting-happy greeting-count] }
  let(:deployed) do
    deployed_doc(cli: { version: 'v0.1.2', sha: 'abc1234' }, http: { version: 'v1.2.3', sha: 'def4567' })
  end
  let(:cli_result) do
    trace_doc(
      channel: 'cli', channel_version: 'v0.1.2', core_version: '0.1.4',
      rows: { 'greeting-happy' => 'passed', 'greeting-count' => 'not_applicable' }
    )
  end
  let(:http_result) { trace_doc(channel: 'http') }
  let(:results) { { 'cli' => cli_result, 'http' => http_result } }

  def build(**overrides)
    ledger_class.build(
      environment: 'prod', suite_version: 'v0.2.0', channels: %w[cli http],
      requirements: requirements, results: results, deployed: deployed, **overrides
    )
  end

  describe 'header' do
    it 'uses the ledger v2 schema and names the environment and the suite version' do
      expect(build).to include(
        'schema' => 'greeterhq.ledger.v2', 'environment' => 'prod', 'suite' => { 'version' => 'v0.2.0' }
      )
    end
  end

  describe 'cells' do
    it 'passes passed, failed, error and not_applicable statuses through' do
      failing = trace_doc(channel: 'http', rows: { 'greeting-happy' => 'error', 'greeting-count' => 'failed' })

      expect(build(results: results.merge('http' => failing))['requirements']).to eq(
        'greeting-count' => { 'cli' => 'not_applicable', 'http' => 'failed' },
        'greeting-happy' => { 'cli' => 'passed', 'http' => 'error' }
      )
    end

    it 'reads missing, not not_applicable, for a requirement with no row' do
      partial = trace_doc(channel: 'http', rows: { 'greeting-happy' => 'passed' })

      expect(build(results: results.merge('http' => partial))['requirements']['greeting-count'])
        .to eq('cli' => 'not_applicable', 'http' => 'missing')
    end

    it 'reads missing for every requirement of a known channel that has no result' do
      cells = build(results: results.merge('http' => nil))['requirements']

      expect(cells.values.map { |row| row['http'] }).to eq(%w[missing missing])
    end
  end

  describe 'columns' do
    it 'is current when the result is from the ledger suite for the deployed version' do
      expect(build['channels']['http']).to include('state' => 'current', 'reasons' => [])
    end

    it 'carries the run context of the channel result' do
      expect(build['channels']['http']).to include(
        'channel_version' => 'v1.2.3', 'core_version' => '0.1.5', 'suite_version' => 'v0.2.0',
        'verification' => 'verified', 'recorded_at' => '2026-11-06T12:00:00Z', 'run_id' => '123456789'
      )
    end

    it 'is missing when the channel has no result' do
      expect(build(results: results.merge('http' => nil))['channels']['http']).to include('state' => 'missing')
    end

    it 'is stale for an older suite version but keeps the last known statuses' do
      old = trace_doc(channel: 'http', suite_version: 'v0.1.0')
      doc = build(results: results.merge('http' => old))

      expect(doc['channels']['http']).to include('state' => 'stale', 'reasons' => ['suite'])
      expect(doc['requirements']['greeting-happy']['http']).to eq('passed')
    end

    it 'is stale when a newer version is deployed than the result covers' do
      newer = deployed_doc(cli: { version: 'v0.1.2' }, http: { version: 'v1.3.0' })

      expect(build(deployed: newer)['channels']['http']).to include('state' => 'stale', 'reasons' => ['channel'])
    end

    it 'names both reasons when the suite is older and the deployed version has moved on' do
      old = trace_doc(channel: 'http', suite_version: 'v0.1.0')
      newer = deployed_doc(cli: { version: 'v0.1.2' }, http: { version: 'v1.3.0' })
      doc = build(results: results.merge('http' => old), deployed: newer)

      expect(doc['channels']['http']['reasons']).to contain_exactly('channel', 'suite')
    end
  end

  describe 'determinism' do
    it 'generates identical output from the same inputs' do
      first = JSON.generate(build)
      second = JSON.generate(build)

      expect(second).to eq(first)
    end

    it 'does not depend on the order of the inputs' do
      shuffled = build(results: results.to_a.reverse.to_h, requirements: requirements.reverse, channels: %w[http cli])

      expect(JSON.generate(shuffled)).to eq(JSON.generate(build))
    end

    it 'carries no generation timestamp of its own' do
      expect(JSON.generate(build)).not_to match(/generated/i)
    end
  end

  describe '.requirements_from_features' do
    it 'returns the sorted, unique requirement slugs from the feature tags' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.feature'), <<~FEATURE)
          @requirement-greeting-happy @scenario-greet-new-guest
          Scenario: one
          @requirement-greeting-count @capability-counting
          Scenario: two
        FEATURE
        File.write(File.join(dir, 'b.feature'), "@requirement-greeting-happy\nScenario: three\n")

        expect(ledger_class.requirements_from_features(dir)).to eq(%w[greeting-count greeting-happy])
      end
    end
  end
end
