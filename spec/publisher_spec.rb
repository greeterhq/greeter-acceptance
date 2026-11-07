# frozen_string_literal: true

RSpec.describe 'Publisher' do
  include_context 'with a ledger remote'

  describe 'the first publication' do
    it 'creates the ledger branch' do
      expect { publish_result }.to change { branch_exists?(remote, 'ledger-prod') }.from(false).to(true)
    end

    it 'publishes the channel result, the deployed record and both generated views' do
      publish_result

      expect(branch_files(remote, 'ledger-prod'))
        .to contain_exactly('LEDGER.md', 'channels/http.json', 'deployed.json', 'ledger.json')
    end

    it 'reports that it committed' do
      expect(publish_result).to eq(:committed)
    end
  end

  describe 'what a publication writes' do
    it "writes only the channel's own result file" do
      publish_result(channel: 'http')
      http_before = branch_file(remote, 'ledger-prod', 'channels/http.json')
      publish_result(channel: 'cli', version: 'v0.1.2')

      expect(branch_file(remote, 'ledger-prod', 'channels/http.json')).to eq(http_before)
      expect(branch_files(remote, 'ledger-prod')).to include('channels/cli.json')
    end

    it "updates only the channel's entry in the deployed record" do
      publish_result(channel: 'http', version: 'v1.2.3')
      publish_result(channel: 'cli', version: 'v0.1.2')
      deployed = stored('deployed.json')

      expect(deployed['schema']).to eq('greeterhq.deployed.v1')
      expect(deployed['channels'].transform_values { |entry| entry['version'] })
        .to eq('cli' => 'v0.1.2', 'http' => 'v1.2.3')
    end

    it 'regenerates the ledger and its rendering from every record on the branch' do
      publish_result(channel: 'http')
      publish_result(channel: 'cli', version: 'v0.1.2')

      expect(stored('ledger.json')['channels'].keys).to contain_exactly('cli', 'http')
      expect(branch_file(remote, 'ledger-prod', 'LEDGER.md')).to include('v0.1.2').and include('v1.2.3')
    end

    it 'makes no commit when nothing would change' do
      publish_result
      commits = commit_count(remote, 'ledger-prod')

      expect(publish_result).to eq(:unchanged)
      expect(commit_count(remote, 'ledger-prod')).to eq(commits)
    end
  end

  describe 'replacing results' do
    it 'replaces a passed result with an error result' do
      publish_result(version: 'v1.2.3')
      publish_result(version: 'v1.2.4', rows: { 'greeting-happy' => 'error', 'greeting-count' => 'error' })

      expect(stored('ledger.json')['requirements']['greeting-happy']['http']).to eq('error')
    end

    %w[error failed].each do |status|
      it "still records the deployed version when every scenario #{status}" do
        publish_result(version: 'v1.2.5', rows: { 'greeting-happy' => status, 'greeting-count' => status })

        expect(stored('deployed.json')['channels']['http']['version']).to eq('v1.2.5')
      end
    end
  end

  describe 'concurrent publication' do
    let(:rival) { build_publisher }
    let(:rival_heads) { [] }
    let(:interfering) do
      lambda do |attempt|
        next unless attempt == 1

        publish_result(channel: 'cli', version: 'v0.1.2', publisher: rival)
        rival_heads << branch_head(remote, 'ledger-prod')
      end
    end
    let(:publisher) { build_publisher(before_push: interfering) }

    it 'retries by re-reading the branch, re-applying its change and regenerating' do
      publish_result(channel: 'http', publisher: publisher)

      expect(publisher.attempts).to eq(2)
      expect(stored('ledger.json')['channels'].keys).to contain_exactly('cli', 'http')
    end

    it "keeps the rival's commit in the history, without merging or forcing" do
      publish_result(channel: 'http', publisher: publisher)

      expect(ancestor?(remote, rival_heads.first, 'ledger-prod')).to be(true)
      expect(merge_commits(remote, 'ledger-prod')).to be_empty
    end

    it 'converges when two channels publish at the same time' do
      remote
      threads = [['http', 'v1.2.3'], ['cli', 'v0.1.2']].map do |channel, version|
        Thread.new do
          Thread.current.report_on_exception = false
          publish_result(channel: channel, version: version)
        end
      end
      threads.each(&:join)

      expect(stored('ledger.json')['channels'].keys).to contain_exactly('cli', 'http')
    end

    it 'gives up with a clear error after the configured attempts when every push is rejected' do
      hook = File.join(remote, 'hooks', 'pre-receive')
      File.write(hook, "#!/bin/sh\necho 'rejected by test' >&2\nexit 1\n")
      File.chmod(0o755, hook)
      limited = build_publisher(max_attempts: 3)

      expect { publish_result(publisher: limited) }.to raise_error(GreeterAcceptance::Publisher::PushRejected)
      expect(limited.attempts).to eq(3)
    end
  end
end
