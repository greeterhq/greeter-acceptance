# frozen_string_literal: true

RSpec.describe 'Publisher guards' do
  include_context 'with a ledger remote'

  let(:refused) { GreeterAcceptance::Publisher::Refused }

  describe 'version ordering' do
    before { publish_result(version: 'v1.2.3') }

    it 'refuses a result for an older channel version and leaves the branch unchanged' do
      head = branch_head(remote, 'ledger-prod')

      expect { publish_result(version: 'v1.2.2') }.to raise_error(refused, /older/)
      expect(branch_head(remote, 'ledger-prod')).to eq(head)
    end

    it 'replaces the result when the version is the same' do
      publish_result(version: 'v1.2.3', rows: { 'greeting-happy' => 'failed', 'greeting-count' => 'passed' })

      expect(stored('ledger.json')['requirements']['greeting-happy']['http']).to eq('failed')
    end

    it 'replaces the result when the version is newer' do
      publish_result(version: 'v1.2.4')

      expect(stored('channels/http.json')['run']['channel_version']).to eq('v1.2.4')
    end

    it 'orders versions by number, not alphabetically' do
      publish_result(version: 'v1.10.0')

      expect(stored('channels/http.json')['run']['channel_version']).to eq('v1.10.0')
    end

    ['latest', 'v1.2', 'v1.2.3 [x](http://evil.test)'].each do |bad|
      it "refuses the non-semantic channel version #{bad.inspect}" do
        expect { publish_result(version: bad) }.to raise_error(refused, /version/)
      end
    end
  end

  describe 'forcing' do
    before { publish_result(version: 'v1.2.3') }

    it 'lets a forced publication replace a newer version and records who forced it' do
      publish_result(version: 'v1.2.2', force: true, actor: 'octocat')

      expect(stored('channels/http.json')['run']).to include('channel_version' => 'v1.2.2', 'forced' => 'octocat')
    end

    it 'leaves the forced marker empty on an ordinary publication' do
      expect(stored('channels/http.json')['run']['forced']).to be_nil
    end
  end

  describe 'suite version' do
    let(:older_suite) { build_publisher(suite_version: 'v0.1.0') }

    before { publish_result(channel: 'http') }

    it 'refuses a publication under an older suite version than the ledger records' do
      expect { publish_result(channel: 'cli', version: 'v0.1.2', publisher: older_suite) }
        .to raise_error(refused, /suite/)
    end

    it 'allows it when forced' do
      expect do
        publish_result(channel: 'cli', version: 'v0.1.2', publisher: older_suite, force: true, actor: 'octocat')
      end
        .not_to raise_error
    end
  end

  describe 'untrusted results' do
    def publish_tampered(channel: 'http')
      result = trace_doc(channel: 'http')
      yield result if block_given?
      deployment = { 'version' => 'v1.2.3', 'sha' => 'def4567', 'run_id' => '1' }
      build_publisher.publish(channel: channel, result: result, deployment: deployment)
    end

    it 'drops fields outside the allowed set at every level' do
      publish_tampered do |result|
        result['evil'] = 'x'
        result['run']['evil'] = 'y'
        result['results'].first['evil'] = 'z'
      end
      stored_result = stored('channels/http.json')

      expect(stored_result.keys).not_to include('evil')
      expect(stored_result['run'].keys).not_to include('evil')
      expect(stored_result['results'].first.keys).not_to include('evil')
    end

    it 'refuses a result that names a channel other than the one being recorded' do
      expect { publish_tampered(channel: 'cli') }.to raise_error(refused, /channel/)
    end

    it 'refuses a status outside passed, failed, error and not_applicable' do
      expect { publish_tampered { |result| result['results'].first['status'] = 'weird' } }
        .to raise_error(refused, /status/)
    end

    it 'refuses a requirement name that carries markup' do
      expect { publish_tampered { |result| result['results'].first['requirement'] = 'a|[x](http://evil.test)' } }
        .to raise_error(refused, /requirement/)
    end

    it 'refuses a result larger than the configured size' do
      expect { publish_result(publisher: build_publisher(max_result_bytes: 100)) }
        .to raise_error(refused, /size/)
    end
  end
end
