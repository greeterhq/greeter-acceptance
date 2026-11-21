# frozen_string_literal: true

require 'yaml'

# adopt-live-docs: the shape of .github/workflows/ci.yml. The workflow is parsed,
# never run. The file quotes "on", so it loads as a string key.
RSpec.describe '.github/workflows/ci.yml' do
  let(:workflow) { YAML.safe_load_file(File.expand_path('../.github/workflows/ci.yml', __dir__)) }
  let(:gate) { "github.event_name == 'schedule' || (github.event_name == 'push' && github.ref == 'refs/heads/main')" }

  def job(name)
    workflow.fetch('jobs').fetch(name)
  end

  def steps(name)
    job(name).fetch('steps')
  end

  def step_named(name, pattern)
    steps(name).find { |step| step['uses'].to_s.match?(pattern) || step['run'].to_s.match?(pattern) } ||
      raise("#{name} has no step matching #{pattern.inspect}")
  end

  # A step's `run`, `env` and `with` as one string, for what it can reference.
  def text_of(step)
    [step['run'], step['env'], step['with']].compact.join("\n")
  end

  # `if: ${{ x }}` and `if: x` are the same condition.
  def condition(job_or_step)
    job_or_step['if'].to_s.sub(/\A\$\{\{\s*/, '').sub(/\s*\}\}\z/, '').strip
  end

  def upload_of(job_name, artifact)
    steps(job_name).find { |s| s['uses'].to_s.start_with?('actions/upload-artifact') && s['with']['name'] == artifact }
  end

  describe 'the rspec job' do
    it 'runs everything but the driver specs with the formatter and uploads a one-day partial trace',
       requirement: 'ci-runs-the-driver-contract-against-real-channels',
       scenario: 'the-rspec-job-excludes-the-driver-specs' do
      run = step_named('rspec', /rspec/)

      expect(job('rspec')).to include('needs' => 'lint', 'permissions' => { 'contents' => 'read' })
      expect(text_of(run)).to include("--exclude-pattern 'spec/drivers/**/*_spec.rb'", '--format RepoTraceFormatter',
                                      'tmp/repo-trace-spec.json')
      expect(upload_of('rspec', 'repo-trace-spec')['with']).to include('path' => 'tmp/repo-trace-spec.json',
                                                                       'retention-days' => 1,
                                                                       'if-no-files-found' => 'error')
    end
  end

  describe 'the drivers job' do
    it 'runs a cli and an http leg with read-only permissions that do not cancel each other',
       requirement: 'ci-runs-the-driver-contract-against-real-channels',
       scenario: 'the-http-leg-targets-stage-from-committed-configuration' do
      expect(job('drivers')).to include('needs' => 'lint', 'permissions' => { 'contents' => 'read' })
      expect(job('drivers')['strategy']).to include('fail-fast' => false, 'matrix' => { 'channel' => %w[cli http] })
    end

    it 'reads the http base URL from the stage entry of config/environments.yml, with no URL in the workflow',
       requirement: 'ci-runs-the-driver-contract-against-real-channels',
       scenario: 'the-http-leg-targets-stage-from-committed-configuration' do
      reader = steps('drivers').find { |step| text_of(step).include?('GREETER_BASE_URL') && step['run'] }

      expect(reader['if']).to include("matrix.channel == 'http'")
      expect(reader['run']).to include('config/environments.yml').and include('stage')
      expect(job('drivers').to_s).not_to match(%r{https?://[a-z0-9-]+\.execute-api})
    end

    it 'looks up the latest greeter-cli release, then follows the record.yml install sequence for the cli leg',
       requirement: 'ci-runs-the-driver-contract-against-real-channels',
       scenario: 'the-cli-leg-installs-the-latest-release-with-the-record-sequence' do
      all = steps('drivers')
      running = ->(needle) { all.index { |step| step['run'].to_s.include?(needle) } }
      # Each setup-ruby step is told apart by the Ruby it installs, not by `uses`.
      ruby_steps = ->(version) { all.each_index.select { |i| all[i].dig('with', 'ruby-version') == version } }
      suite = ruby_steps.call('${{ env.RUBY_VERSION }}')
      declared = ruby_steps.call('${{ steps.declared.outputs.ruby }}')
      lookup = running.call('gh release view')
      fetch = running.call('bin/cli-release fetch')
      ruby_version = running.call('bin/cli-release ruby-version')
      install = running.call('bin/cli-release install')
      rspec = running.call('_driver_spec.rb')

      expect([lookup, fetch, ruby_version, install, rspec]).to all(be_an(Integer))
      expect(declared.size).to eq(1)
      expect(suite).to include(a_value < fetch)
      expect([lookup, fetch, ruby_version]).to eq([lookup, fetch, ruby_version].sort)
      expect(declared.first).to be_between(ruby_version + 1, install - 1)
      expect(suite).to include(a_value_between(install + 1, rspec - 1))
      expect(steps('drivers').map { |s| s['run'].to_s }.join).to include('greeterhq/greeter-cli', 'gh api')
    end

    it 'has every step that holds a token before the fetch and none after it',
       requirement: 'ci-runs-the-driver-contract-against-real-channels',
       scenario: 'the-cli-leg-installs-the-latest-release-with-the-record-sequence' do
      all = steps('drivers')
      fetch = all.index { |step| step['run'].to_s.include?('bin/cli-release fetch') }
      # The token-order rule from harden-candidate-install: nothing after the fetch
      # references a secret, the job token or a minted token's output.
      token = /GH_TOKEN|github\.token|secrets\.|steps\.[\w-]+\.outputs\.token/
      holders = all.each_index.select { |i| text_of(all[i]).match?(token) }

      expect(fetch).not_to be_nil
      expect(holders).not_to be_empty
      expect(holders.max).to be < fetch
    end

    it 'runs each leg its own driver spec with the formatter and uploads its own one-day trace',
       requirement: 'ci-runs-the-driver-contract-against-real-channels',
       scenario: 'each-leg-runs-its-driver-spec-and-writes-its-own-trace' do
      run = steps('drivers').find { |step| step['run'].to_s.include?('_driver_spec.rb') }
      upload = steps('drivers').find { |s| s['uses'].to_s.start_with?('actions/upload-artifact') }

      expect(text_of(run)).to include('spec/drivers/', 'RepoTraceFormatter', 'tmp/repo-trace-drivers-')
      expect(upload['with']).to include('name' => 'repo-trace-drivers-${{ matrix.channel }}', 'retention-days' => 1,
                                        'if-no-files-found' => 'error')
    end
  end

  describe 'the trace job' do
    it 'needs both test jobs, runs unless cancelled, with read-only permissions and no persisted checkout token',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'trace-job-merges-and-uploads-on-main-and-schedule' do
      checkout = step_named('trace', %r{actions/checkout})

      expect(Array(job('trace')['needs']).sort).to eq(%w[drivers rspec])
      expect(condition(job('trace'))).to eq('!cancelled()')
      expect(job('trace')['permissions']).to eq('contents' => 'read')
      expect(checkout['with']).to include('persist-credentials' => false)
      expect(workflow['on']['schedule']).to eq([{ 'cron' => '17 6 * * 1' }])
    end

    it 'downloads the three partial traces by name from this run only',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'trace-job-merges-and-uploads-on-main-and-schedule' do
      downloads = steps('trace').select { |s| s['uses'].to_s.start_with?('actions/download-artifact') }

      expect(downloads.map { |s| s['with']['name'] }).to contain_exactly(
        'repo-trace-spec', 'repo-trace-drivers-cli', 'repo-trace-drivers-http'
      )
      expect(downloads.flat_map { |s| s['with'].keys }).not_to include('run-id', 'merge-multiple')
    end

    it 'merges only when both test jobs succeeded and uploads repo-trace for 90 days on the gate',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'trace-job-merges-and-uploads-on-main-and-schedule' do
      merge = step_named('trace', %r{bin/merge-repo-trace})
      upload = upload_of('trace', 'repo-trace')

      expect(condition(merge)).to include("needs.rspec.result == 'success'", "needs.drivers.result == 'success'")
      expect(condition(upload)).to include(gate)
      expect(upload['with']).to include('retention-days' => 90, 'if-no-files-found' => 'error')
    end

    it 'ends with a step that fails the job when a test job did not succeed',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'failed-runs-and-pull-requests-publish-nothing' do
      last = steps('trace').last

      expect(last['run'].to_s.strip).to eq('exit 1')
      expect(condition(last)).to include("needs.rspec.result != 'success'", "needs.drivers.result != 'success'")
    end
  end

  describe 'the notify-docs job' do
    it 'dispatches docs-refresh for greeter-acceptance with a token minted in the job',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'notify-docs-dispatches-docs-refresh' do
      token = step_named('notify-docs', %r{actions/create-github-app-token@v3})
      dispatch = step_named('notify-docs', /docs-refresh/)

      expect(job('notify-docs')).to include('needs' => 'trace', 'permissions' => {})
      expect(condition(job('notify-docs'))).to eq(gate)
      expect(token['with']).to include(
        'client-id' => '${{ vars.DISPATCH_APP_CLIENT_ID }}', 'private-key' => '${{ secrets.DISPATCH_APP_PRIVATE_KEY }}',
        'owner' => 'greeterhq', 'repositories' => 'greeter-docs', 'permission-contents' => 'write'
      )
      expect(dispatch['env']).to include('GH_TOKEN' => "${{ steps.#{token['id']}.outputs.token }}")
      expect(dispatch['run']).to include('repos/greeterhq/greeter-docs/dispatches', 'event_type=docs-refresh',
                                         'client_payload[repo]=greeter-acceptance')
    end

    it 'does not run for pull requests, so a pull request publishes nothing',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'failed-runs-and-pull-requests-publish-nothing' do
      expect(condition(job('notify-docs'))).not_to include('pull_request')
      expect(condition(upload_of('trace', 'repo-trace'))).not_to include('pull_request')
    end

    it 'has top-level read-only permissions and no ${{ }} expression in the run steps of trace and notify-docs',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'workflow-credentials-are-least-privilege' do
      runs = %w[trace notify-docs].flat_map { |name| steps(name).filter_map { |step| step['run'] } }

      expect(workflow['permissions']).to eq('contents' => 'read')
      expect(runs).not_to be_empty
      expect(runs.grep(/\$\{\{/)).to eq([])
    end
  end

  describe 'concurrency' do
    it 'keeps main and weekly runs apart and cancels only pull-request runs',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'main-and-weekly-runs-do-not-cancel-each-other' do
      expect(workflow['concurrency']).to eq(
        'group' => 'ci-${{ github.event_name }}-${{ github.ref }}',
        'cancel-in-progress' => "${{ github.event_name == 'pull_request' }}"
      )
    end
  end
end
