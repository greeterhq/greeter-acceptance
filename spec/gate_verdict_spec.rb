# frozen_string_literal: true

RSpec.describe 'GateVerdict' do
  let(:gate) { GreeterAcceptance::GateVerdict }
  let(:rows) { { 'greeting-happy' => 'passed', 'greeting-count' => 'passed' } }
  let(:run) { {} }
  let(:trace) { trace_doc(channel: 'http', rows: rows, **run) }

  def verdict(**options)
    gate.evaluate(trace, acceptance_ref: 'v0.2.0', expected_version: 'v1.2.3', **options)
  end

  describe 'results' do
    it 'passes when every scenario passed' do
      expect(verdict).to be_passed
    end

    it 'fails when a scenario failed and names the requirement' do
      trace['results'].first['status'] = 'failed'

      expect(verdict).not_to be_passed
      expect(verdict.reasons.join).to include(trace['results'].first['requirement'])
    end

    it 'fails when a scenario errored' do
      trace['results'].first['status'] = 'error'

      expect(verdict).not_to be_passed
    end

    context 'when some scenarios are not applicable' do
      let(:rows) { { 'greeting-happy' => 'passed', 'greeting-count' => 'not_applicable' } }

      it 'does not fail because of them' do
        expect(verdict).to be_passed
      end
    end
  end

  describe 'the version tested' do
    context 'when the observed version differs from the candidate' do
      let(:run) { { channel_version: 'v1.2.2', verification: 'mismatch' } }

      it 'fails and names both versions' do
        expect(verdict).not_to be_passed
        expect(verdict.reasons.join).to include('v1.2.2').and include('v1.2.3')
      end
    end

    context 'when the version changed during the run' do
      let(:run) { { verification: 'inconsistent' } }

      it 'fails' do
        expect(verdict).not_to be_passed
      end
    end

    context 'when no version could be observed' do
      let(:run) { { verification: 'unobserved' } }

      it 'fails unless an unverified run is allowed' do
        expect(verdict).not_to be_passed
      end

      it 'passes and is marked unverified when an unverified run is allowed' do
        result = verdict(allow_unverified: true)

        expect(result).to be_passed
        expect(result).to be_unverified
      end
    end

    it 'is not marked unverified when the version was verified' do
      expect(verdict).not_to be_unverified
    end
  end

  describe 'the acceptance reference' do
    [nil, ''].each do |missing|
      it "fails when the caller supplies #{missing.inspect}" do
        result = verdict(acceptance_ref: missing)

        expect(result).not_to be_passed
        expect(result.reasons.join).to match(/acceptance reference/i)
      end
    end
  end
end
