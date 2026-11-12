# frozen_string_literal: true

require 'fileutils'
require 'json'

# A local bare git repository standing in for the remote that holds a ledger
# branch, with helpers to build a publisher against it and publish results.
RSpec.shared_context 'with a ledger remote' do
  let(:remote) { init_bare_remote }

  after { FileUtils.remove_entry(remote) }

  def build_publisher(**overrides)
    GreeterAcceptance::Publisher.new(
      remote: remote, branch: 'ledger-prod', environment: 'prod', suite_version: 'v0.2.0',
      channels: %w[cli http], requirements: %w[greeting-happy greeting-count], **overrides
    )
  end

  def publish_result(channel: 'http', version: 'v1.2.3', rows: LedgerFixtures::PASSING_ROWS, publisher: nil, **options)
    publisher ||= build_publisher
    result = trace_doc(channel: channel, channel_version: version, rows: rows)
    deployment = { 'version' => version, 'sha' => 'def4567', 'run_id' => '1' }
    publisher.publish(channel: channel, result: result, deployment: deployment, **options)
  end

  def stored(path, branch: 'ledger-prod')
    JSON.parse(branch_file(remote, branch, path))
  end
end
