# frozen_string_literal: true

RSpec.describe 'LedgerRenderer' do
  let(:renderer) { GreeterAcceptance::LedgerRenderer }
  let(:ledger) do
    {
      'schema' => 'greeterhq.ledger.v2', 'environment' => 'prod', 'suite' => { 'version' => 'v0.2.0' },
      'channels' => {
        'cli' => column(
          'current', [], 'channel_version' => 'v0.1.2', 'core_version' => '0.1.4',
                         'recorded_at' => '2026-11-05T09:00:00Z', 'run_id' => '812'
        ),
        'http' => column(
          'stale', ['suite'], 'suite_version' => 'v0.1.0', 'recorded_at' => '2026-10-01T10:00:00Z', 'run_id' => '815'
        )
      },
      'requirements' => {
        'greeting-count' => { 'cli' => 'not_applicable', 'http' => 'passed' },
        'greeting-happy' => { 'cli' => 'passed', 'http' => 'passed' }
      }
    }
  end

  def column(state, reasons, overrides = {})
    {
      'state' => state, 'reasons' => reasons, 'channel_version' => 'v1.2.3', 'core_version' => '0.1.5',
      'suite_version' => 'v0.2.0', 'verification' => 'verified', 'recorded_at' => '2026-11-06T12:00:00Z',
      'run_id' => '1'
    }.merge(overrides)
  end

  describe 'context' do
    it 'names the environment and the suite version' do
      expect(renderer.render(ledger)).to include('prod').and include('v0.2.0')
    end

    it 'shows each channel version and core version' do
      markdown = renderer.render(ledger)

      expect(markdown).to include('v0.1.2').and include('0.1.4').and include('v1.2.3')
    end

    it 'shows when and by which run each channel was recorded' do
      markdown = renderer.render(ledger)

      expect(markdown).to include('2026-11-05').and include('812').and include('815')
    end
  end

  describe 'statuses' do
    it 'renders each requirement with its status per channel' do
      expect(renderer.render(ledger)).to match(/greeting-count.*not_applicable.*passed/)
    end

    it 'marks a stale column as stale' do
      expect(renderer.render(ledger)).to include('stale')
    end

    it 'shows missing for a column with no result' do
      empty = ledger.merge('channels' => ledger['channels'].merge('http' => { 'state' => 'missing', 'reasons' => [] }))
      empty['requirements'] = empty['requirements'].transform_values { |row| row.merge('http' => 'missing') }

      expect(renderer.render(empty)).to include('missing')
    end
  end

  describe 'safety' do
    it 'renders markup in a version as plain text' do
      hostile = 'v1.2.3 <script>alert(1)</script> [x](http://evil.test)'
      ledger['channels']['http']['channel_version'] = hostile
      markdown = renderer.render(ledger)

      expect(markdown).not_to include('<script>')
      expect(markdown).not_to include('](http://evil.test)')
      expect(markdown).to include('alert(1)')
    end
  end

  describe 'determinism' do
    it 'renders identically each time' do
      first = renderer.render(ledger)
      second = renderer.render(ledger)

      expect(second).to eq(first)
    end

    it 'carries no generation timestamp' do
      expect(renderer.render(ledger)).not_to match(/generated/i)
    end
  end
end
