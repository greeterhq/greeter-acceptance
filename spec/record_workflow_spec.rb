# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'

# adopt-live-docs: the shape of .github/workflows/record.yml after the `notify-docs`
# job is added. The workflow is parsed, never run.
RSpec.describe '.github/workflows/record.yml' do
  let(:path) { File.expand_path('../.github/workflows/record.yml', __dir__) }
  let(:workflow) { YAML.safe_load_file(path) }

  def job(name)
    workflow.fetch('jobs').fetch(name)
  end

  def steps(name)
    job(name).fetch('steps')
  end

  def text_of(step)
    [step['run'], step['env'], step['with']].compact.join("\n")
  end

  describe 'the notify-docs job' do
    it 'follows a successful publish, once per environment of the run',
       requirement: 'record-mode-notifies-docs-after-publishing',
       scenario: 'notify-docs-follows-a-successful-publish-once-per-environment' do
      notify = job('notify-docs')
      dispatch = steps('notify-docs').find { |step| step['run'].to_s.include?('docs-refresh') }

      expect(Array(notify['needs']).sort).to eq(%w[publish resolve])
      expect(notify['if']).to eq("always() && needs.publish.result == 'success'")
      expect(notify['permissions']).to eq({})
      expect(notify['strategy']).to include(
        'fail-fast' => false, 'matrix' => { 'environment' => '${{ fromJSON(needs.resolve.outputs.environments) }}' }
      )
      expect(dispatch['run']).to include('client_payload[repo]=greeter-acceptance',
                                         'client_payload[ledger]=$ENVIRONMENT')
      expect(dispatch['env']).to include('ENVIRONMENT' => '${{ matrix.environment }}')
      expect(dispatch['run']).not_to include('${{')
    end

    it 'mints its own greeterhq-dispatch token and never touches the ledger-writer token',
       requirement: 'record-mode-notifies-docs-after-publishing', scenario: 'notify-docs-uses-its-own-token' do
      token = steps('notify-docs').find { |step| step['uses'].to_s.start_with?('actions/create-github-app-token@v3') }
      dispatch = steps('notify-docs').find { |step| step['run'].to_s.include?('docs-refresh') }

      expect(token['with']).to include(
        'client-id' => '${{ vars.DISPATCH_APP_CLIENT_ID }}', 'private-key' => '${{ secrets.DISPATCH_APP_PRIVATE_KEY }}',
        'owner' => 'greeterhq', 'repositories' => 'greeter-docs', 'permission-contents' => 'write'
      )
      expect(dispatch['env']).to include('GH_TOKEN' => "${{ steps.#{token['id']}.outputs.token }}")
      expect(job('notify-docs').to_s).not_to include('LEDGER_APP')
    end
  end

  describe 'the publish job' do
    it 'has no dispatch step, no DISPATCH_APP reference and mints only the ledger-writer token',
       requirement: 'record-mode-notifies-docs-after-publishing', scenario: 'the-publish-job-is-unchanged' do
      minted = steps('publish').select { |step| step['uses'].to_s.start_with?('actions/create-github-app-token') }

      expect(job('publish')['permissions']).to eq('contents' => 'read')
      expect(job('publish').to_s).not_to include('DISPATCH_APP')
      expect(job('publish').to_s).not_to include('docs-refresh')
      expect(minted.map { |step| step['with']['client-id'] }).to eq(['${{ vars.LEDGER_APP_CLIENT_ID }}'])
      expect(minted.map { |step| step['with']['repositories'] }).to eq(['greeter-acceptance'])
    end
  end

  describe 'the environments output of resolve' do
    let(:dir) { Dir.mktmpdir('record-environments') }

    after { FileUtils.remove_entry(dir) }

    it 'lists each environment of the resolved matrix once, as a JSON array',
       requirement: 'record-mode-notifies-docs-after-publishing',
       scenario: 'the-environments-output-lists-each-environment-once' do
      expect(job('resolve')['outputs']).to include('environments' => '${{ steps.resolve.outputs.environments }}')

      line = job('resolve')['steps'].filter_map { |step| step['run'] }.join("\n").lines
                                    .find { |l| l.include?('environments=') }
      matrix = { 'matrix' => { 'include' => [
        { 'environment' => 'stage', 'channel' => 'cli' }, { 'environment' => 'prod', 'channel' => 'cli' },
        { 'environment' => 'stage', 'channel' => 'http' }, { 'environment' => 'prod', 'channel' => 'http' }
      ] } }
      File.write(File.join(dir, 'resolved.json'), JSON.generate(matrix))
      output, = Open3.capture2e({ 'RUNNER_TEMP' => dir }, 'sh', '-c', line.strip)

      expect(output.strip).to start_with('environments=')
      expect(JSON.parse(output.strip.delete_prefix('environments='))).to contain_exactly('prod', 'stage')
    end
  end
end
