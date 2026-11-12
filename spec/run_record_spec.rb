# frozen_string_literal: true

require 'json'
require 'tmpdir'

RSpec.describe 'RunRecord' do
  let(:clock) { Struct.new(:now).new(Time.utc(2026, 11, 6, 12, 0, 0)) }
  let(:expected_version) { 'v1.2.3' }
  let(:record) do
    GreeterAcceptance::RunRecord.new(
      channel: :http, environment: 'prod', suite_version: 'v0.2.0',
      expected_version: expected_version, expected_sha: 'def4567',
      run_id: '123456789', clock: clock
    )
  end

  def build_info(version, core: '0.1.5')
    GreeterAcceptance::Ports::BuildInfo.new(channel_version: version, core_version: core)
  end

  describe '.status_for' do
    let(:run_record) { GreeterAcceptance::RunRecord }

    it 'is passed when nothing failed and no infrastructure error was seen' do
      expect(run_record.status_for(failed: false, infrastructure_error: false)).to eq(:passed)
    end

    it 'is failed when an assertion failed and no infrastructure error was seen' do
      expect(run_record.status_for(failed: true, infrastructure_error: false)).to eq(:failed)
    end

    it 'is error when an infrastructure error was seen, even if an assertion also failed' do
      expect(run_record.status_for(failed: true, infrastructure_error: true)).to eq(:error)
    end

    it 'is error when an infrastructure error was seen but nothing else failed' do
      expect(run_record.status_for(failed: false, infrastructure_error: true)).to eq(:error)
    end
  end

  describe '#row' do
    it 'records the requirement and scenario slugs from the tags with the status' do
      record.row(tag_names: %w[@requirement-greeting-happy @scenario-greet-new-guest], status: :passed)

      expect(record.document['results']).to eq(
        [{ 'requirement' => 'greeting-happy', 'scenario' => 'greet-new-guest', 'status' => 'passed' }]
      )
    end

    it 'records the missing capabilities of a not-applicable row' do
      record.row(
        tag_names: %w[@requirement-greeting-count @scenario-count-new-guest @capability-counting],
        status: :not_applicable, missing_capabilities: [:counting]
      )

      expect(record.document['results'].first)
        .to include('status' => 'not_applicable', 'missing_capabilities' => ['counting'])
    end

    it 'records an error row' do
      record.row(tag_names: %w[@requirement-greeting-happy @scenario-greet-new-guest], status: :error)

      expect(record.document['results'].first['status']).to eq('error')
    end
  end

  describe '#verification' do
    it 'is unobserved when nothing was observed' do
      expect(record.verification).to eq(:unobserved)
    end

    it 'ignores an unobservable observation' do
      record.observe(nil)

      expect(record.verification).to eq(:unobserved)
    end

    it 'is verified when the observed version equals the expected version' do
      record.observe(build_info('v1.2.3'))

      expect(record.verification).to eq(:verified)
    end

    it 'ignores a leading v when comparing versions' do
      record.observe(build_info('1.2.3'))

      expect(record.verification).to eq(:verified)
    end

    it 'stays verified when the same version is observed repeatedly' do
      3.times { record.observe(build_info('v1.2.3')) }

      expect(record.verification).to eq(:verified)
    end

    it 'is mismatch when the observed version differs from the expected version' do
      record.observe(build_info('v1.2.2'))

      expect(record.verification).to eq(:mismatch)
    end

    it 'is inconsistent when two different versions are observed, even if one matches' do
      record.observe(build_info('v1.2.3'))
      record.observe(build_info('v1.2.4'))

      expect(record.verification).to eq(:inconsistent)
    end
  end

  describe '#document' do
    before { record.observe(build_info('v1.2.3')) }

    it 'uses the traceability v2 schema' do
      expect(record.document['schema']).to eq('greeterhq.traceability.v2')
    end

    it 'records the run context' do
      expect(record.document['run']).to include(
        'channel' => 'http', 'environment' => 'prod', 'suite_version' => 'v0.2.0',
        'recorded_at' => '2026-11-06T12:00:00Z', 'run_id' => '123456789'
      )
    end

    it 'records the observed versions, the sha and the verification state' do
      expect(record.document['run']).to include(
        'channel_version' => 'v1.2.3', 'core_version' => '0.1.5',
        'channel_sha' => 'def4567', 'verification' => 'verified'
      )
    end

    it 'records the release time it is given' do
      timed = GreeterAcceptance::RunRecord.new(
        channel: :cli, environment: 'prod', suite_version: 'v0.2.0',
        released_at: '2026-11-01T09:30:00Z', clock: clock
      )

      expect(timed.document['run']['released_at']).to eq('2026-11-01T09:30:00Z')
    end
  end

  # CI passes every optional field through the environment, and a step output that
  # was never set arrives as an empty string. An empty value means unknown.
  describe 'optional run context given as empty strings' do
    let(:blank) do
      GreeterAcceptance::RunRecord.new(
        channel: :http, environment: 'prod', suite_version: 'v0.2.0',
        expected_version: 'v1.2.3', expected_sha: '', run_id: '', released_at: '', clock: clock
      )
    end

    it 'records an empty release time as null' do
      expect(blank.document['run']['released_at']).to be_nil
    end

    it 'records an empty sha and run id as null' do
      expect(blank.document['run']).to include('channel_sha' => nil, 'run_id' => nil)
    end
  end

  describe 'attribution' do
    it 'attributes a mismatched run to the version actually observed, not the expected one' do
      record.observe(build_info('v1.2.2'))

      expect(record.document['run']).to include('channel_version' => 'v1.2.2', 'verification' => 'mismatch')
    end

    it 'marks a run with no observations as unobserved' do
      expect(record.document['run']['verification']).to eq('unobserved')
    end
  end

  describe '#write' do
    it 'writes the document as JSON to the given path' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'tmp', 'traceability.json')
        record.write(path)

        expect(JSON.parse(File.read(path))).to eq(record.document)
      end
    end
  end
end
