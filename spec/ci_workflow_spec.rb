# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'

# adopt-live-docs: the shape of .github/workflows/ci.yml. The workflow is parsed,
# never run. The file quotes "on", so it loads as a string key.
RSpec.describe '.github/workflows/ci.yml' do
  let(:workflow) { YAML.safe_load_file(File.expand_path('../.github/workflows/ci.yml', __dir__)) }
  let(:gate) { "github.event_name == 'schedule' || (github.event_name == 'push' && github.ref == 'refs/heads/main')" }
  # add-pact-consumer helpers.
  let(:root) { File.expand_path('..', __dir__) }
  let(:publish_gate) do
    "github.event_name == 'push' && (github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v'))"
  end
  let(:on_tag) { "startsWith(github.ref, 'refs/tags/v')" }

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

  def publish_steps
    steps('pact-publish')
  end

  def broker_step?(step)
    step['run'].to_s.include?('pact-broker')
  end

  def token_step?(step)
    text_of(step).include?('secrets.PACT_BROKER_TOKEN')
  end

  # The part of a `run:` after `pact-broker`, i.e. the pact-broker command line.
  def broker_command(step)
    step['run'].to_s.split('pact-broker', 2).last.to_s
  end

  # Runs a step's `run:` the way GitHub runs it (bash -eo pipefail), outside
  # bundler so only the standard library is available. Literal step env values
  # are kept; `${{ }}` values come from `env`.
  def run_step(step, env:, chdir:)
    literal = (step['env'] || {}).reject { |_key, value| value.to_s.include?('${{') }.transform_values(&:to_s)
    command = ['bash', '--noprofile', '--norc', '-eo', 'pipefail', '-c', step.fetch('run')]
    runner = -> { Open3.capture2e(literal.merge(env), *command, chdir: chdir) }
    defined?(Bundler) ? Bundler.with_unbundled_env(&runner) : runner.call
  end

  def pact_check_step
    publish_steps.find { |s| s['run'].to_s.include?('greeter-acceptance-greeter-http.json') && !broker_step?(s) } ||
      raise('pact-publish has no pact check step')
  end

  def tag_check_step
    publish_steps.find { |s| s['run'].to_s.include?('GITHUB_REF_NAME') && !broker_step?(s) } ||
      raise('pact-publish has no tag check step')
  end

  def ancestry_step
    publish_steps.find { |s| s['run'].to_s.include?('merge-base --is-ancestor') } ||
      raise('pact-publish has no ancestry check step')
  end

  def pacts_download
    publish_steps.find do |s|
      s['uses'].to_s.start_with?('actions/download-artifact') && s.dig('with', 'name') == 'pacts'
    end
  end

  # A workspace holding the downloaded pacts directory with the given files.
  def workspace_with_pacts(files)
    dir = Dir.mktmpdir('pact-publish')
    pacts = File.join(dir, pacts_download.dig('with', 'path') || '.')
    FileUtils.mkdir_p(pacts)
    files.each { |name, content| File.write(File.join(pacts, name), JSON.generate(content)) }
    dir
  end

  def pact_document(consumer: 'greeter-acceptance', provider: 'greeter-http')
    { 'consumer' => { 'name' => consumer }, 'provider' => { 'name' => provider }, 'interactions' => [] }
  end

  def run_pact_check(files, url: 'https://broker.example.test')
    dir = workspace_with_pacts(files)
    run_step(pact_check_step, env: { 'PACT_BROKER_BASE_URL' => url, 'GITHUB_WORKSPACE' => dir }, chdir: dir)
  end

  # A repo whose origin/main holds one commit and whose side branch holds one
  # more commit that is not on main.
  def repo_with_side_commit
    dir = Dir.mktmpdir('pact-tag')
    git = ->(*args) { run_git('-C', dir, '-c', 'user.name=t', '-c', 'user.email=t@example.test', *args).strip }
    git.call('init', '-q', '-b', 'main')
    git.call('commit', '-q', '--allow-empty', '-m', 'on main')
    on_main = git.call('rev-parse', 'HEAD')
    git.call('update-ref', 'refs/remotes/origin/main', on_main)
    git.call('checkout', '-q', '-b', 'side')
    git.call('commit', '-q', '--allow-empty', '-m', 'off main')
    [dir, on_main, git.call('rev-parse', 'HEAD')]
  end

  # How many examples rspec selects from the :pact-tagged fixture, which lies
  # outside spec/pact/ so only spec_helper's filter can exclude it.
  def pact_fixture_count(*options)
    Dir.mktmpdir('pact-filter') do |dir|
      out = File.join(dir, 'result.json')
      output, status = Open3.capture2e('bundle', 'exec', 'rspec', *options, '--format', 'json', '--out', out,
                                       'spec/fixtures/pact_filter/tagged.rb', chdir: root)
      raise "rspec failed: #{output}" unless status.success?

      JSON.parse(File.read(out)).dig('summary', 'example_count')
    end
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
    it 'needs the three test jobs, runs unless cancelled, with read-only permissions and no persisted checkout token',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'trace-job-merges-and-uploads-on-main-and-schedule' do
      checkout = step_named('trace', %r{actions/checkout})

      expect(Array(job('trace')['needs']).sort).to eq(%w[drivers pact rspec])
      expect(condition(job('trace'))).to eq('!cancelled()')
      expect(job('trace')['permissions']).to eq('contents' => 'read')
      expect(checkout['with']).to include('persist-credentials' => false)
      expect(workflow['on']['schedule']).to eq([{ 'cron' => '17 6 * * 1' }])
    end

    it 'downloads the four partial traces by name from this run only',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'trace-job-merges-and-uploads-on-main-and-schedule' do
      downloads = steps('trace').select { |s| s['uses'].to_s.start_with?('actions/download-artifact') }

      expect(downloads.map { |s| s['with']['name'] }).to contain_exactly(
        'repo-trace-spec', 'repo-trace-drivers-cli', 'repo-trace-drivers-http', 'repo-trace-pact'
      )
      expect(downloads.flat_map { |s| s['with'].keys }).not_to include('run-id', 'merge-multiple')
    end

    it 'merges all four only when the three test jobs succeeded and uploads repo-trace for 90 days on the gate',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'trace-job-merges-and-uploads-on-main-and-schedule' do
      merge = step_named('trace', %r{bin/merge-repo-trace})
      upload = upload_of('trace', 'repo-trace')

      expect(condition(merge)).to include("needs.rspec.result == 'success'", "needs.drivers.result == 'success'",
                                          "needs.pact.result == 'success'")
      expect(merge['run']).to include('tmp/traces/pact/repo-trace-pact.json')
      expect(condition(upload)).to include(gate)
      expect(upload['with']).to include('retention-days' => 90, 'if-no-files-found' => 'error')
    end

    it 'ends with a step that fails the job when a test job did not succeed',
       requirement: 'ci-publishes-the-merged-trace-on-main-and-weekly',
       scenario: 'failed-runs-and-pull-requests-publish-nothing' do
      last = steps('trace').last

      expect(last['run'].to_s.strip).to eq('exit 1')
      expect(condition(last)).to include("needs.rspec.result != 'success'", "needs.drivers.result != 'success'",
                                         "needs.pact.result != 'success'")
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

  # ═══ add-pact-consumer ════════════════════════════════════════════════════
  describe 'the default run' do
    it 'excludes :pact examples through spec_helper and runs them when the pact tag is selected',
       requirement: 'pact-specs-are-excluded-from-the-default-run',
       scenario: 'the-default-run-skips-the-pact-specs' do
      rspec = text_of(step_named('rspec', /rspec/))

      expect(pact_fixture_count).to eq(0)
      expect(pact_fixture_count('-t', 'pact')).to eq(1)
      expect(rspec).not_to include('-t pact', '--tag pact', 'spec/pact')
    end
  end

  describe 'the pact job' do
    it 'runs the pact specs on every trigger, read-only and without secrets, and uploads a one-day partial trace',
       requirement: 'ci-runs-the-pact-specs-on-every-run',
       scenario: 'the-pact-job-runs-the-specs-and-uploads-a-partial-trace' do
      run = step_named('pact', /rspec -t pact/)

      expect(job('pact')).to include('needs' => 'lint', 'permissions' => { 'contents' => 'read' })
      expect(job('pact')).not_to have_key('if')
      expect(job('pact').to_s).not_to include('secrets.')
      expect(text_of(run)).to include('bundle exec rspec -t pact spec/pact/providers', '--format RepoTraceFormatter',
                                      'tmp/repo-trace-pact.json')
      expect(upload_of('pact', 'repo-trace-pact')['with']).to include('path' => 'tmp/repo-trace-pact.json',
                                                                      'retention-days' => 1,
                                                                      'if-no-files-found' => 'error')
    end
  end

  describe 'the pact-publish job' do
    it 'publishes from main with the main branch, using the pinned pact-cli image and this run\'s pacts',
       requirement: 'ci-publishes-the-pact-only-from-main-and-suite-tags',
       scenario: 'main-publishes-with-the-main-branch' do
      main = publish_steps.find { |s| broker_step?(s) && s['run'].include?('publish') && s['run'].include?('--branch') }

      expect(job('pact-publish')).to include('needs' => 'pact', 'permissions' => { 'contents' => 'read' })
      expect(condition(job('pact-publish'))).to eq(publish_gate)
      expect(workflow.fetch('env').fetch('PACT_CLI_IMAGE'))
        .to match(%r{\Apactfoundation/pact-cli:[\w.-]+@sha256:\h{64}\z})
      expect(condition(main)).to include("github.ref == 'refs/heads/main'")
      expect(main['run']).to include('"$PACT_CLI_IMAGE"', 'pact-broker publish', '--branch main')
      expect(main['run']).to match(/--consumer-app-version "?\$GITHUB_SHA"?/)
      expect(pacts_download['with'].keys).not_to include('run-id', 'merge-multiple')
    end

    it 'never publishes for a pull request or the schedule, and no other job calls the broker',
       requirement: 'ci-publishes-the-pact-only-from-main-and-suite-tags',
       scenario: 'a-pull-request-publishes-no-pact' do
      others = workflow.fetch('jobs').except('pact-publish')

      expect(condition(job('pact-publish'))).to eq(publish_gate)
      expect(condition(job('pact-publish'))).not_to include('pull_request', 'schedule')
      expect(others.select { |_name, other| other.to_s.include?('pact-broker') }.keys).to eq([])
    end

    it 'on a tag checks the commit is on main, publishes without --branch or --tag, then records stage and prod',
       requirement: 'a-suite-tag-on-main-publishes-and-records-deployments',
       scenario: 'a-tag-publishes-then-records-stage-and-prod' do
      ancestry = publish_steps.index(ancestry_step)
      publish = publish_steps.index do |s|
        broker_step?(s) && s['run'].include?('publish') && !s['run'].include?('--branch')
      end
      records = publish_steps.each_index.select { |i| publish_steps[i]['run'].to_s.include?('record-deployment') }
      record_text = records.map { |i| publish_steps[i]['run'] }.join("\n")

      expect(publish).not_to be_nil
      expect([condition(ancestry_step), condition(publish_steps[publish])]).to all(include(on_tag))
      expect(ancestry).to be < publish
      expect(publish_steps[publish]['run']).not_to match(/--tag\b/)
      expect(records).to all(be > publish)
      expect(records.map { |i| condition(publish_steps[i]) }).to all(include(on_tag))
      expect(record_text).to include('--pacticipant greeter-acceptance', '--environment stage', '--environment prod')
      expect(record_text).to match(/--version "?\$GITHUB_SHA"?/)
    end

    it 'fails the ancestry check for a tag off main, so nothing after it runs',
       requirement: 'a-suite-tag-on-main-publishes-and-records-deployments',
       scenario: 'a-tag-off-main-fails-before-publishing' do
      dir, on_main, off_main = repo_with_side_commit
      later = publish_steps.drop(publish_steps.index(ancestry_step) + 1)

      expect(run_step(ancestry_step, env: { 'GITHUB_SHA' => on_main }, chdir: dir).last).to be_success
      expect(run_step(ancestry_step, env: { 'GITHUB_SHA' => off_main }, chdir: dir).last).not_to be_success
      expect(later.map { |s| condition(s) }.grep(/always\(\)|failure\(\)/)).to eq([])
    end

    it 'gives the broker token only to the pact-broker steps, each with its own env',
       requirement: 'the-broker-token-reaches-only-the-publish-steps',
       scenario: 'the-token-is-scoped-to-the-pact-broker-steps' do
      holders = workflow.fetch('jobs').flat_map { |name, j| j.fetch('steps', []).map { |s| [name, s] } }
                        .select { |_name, step| token_step?(step) }
      broker_envs = publish_steps.select { |s| broker_step?(s) }.map { |s| s['env'] || {} }
      level_envs = [workflow['env'], *workflow.fetch('jobs').values.map { |j| j['env'] }].compact

      expect(holders).not_to be_empty
      expect(holders.map(&:first).uniq).to eq(['pact-publish'])
      expect(holders.map { |_name, step| broker_step?(step) }).to all(be(true))
      expect(broker_envs).to all(include('PACT_BROKER_BASE_URL' => '${{ vars.PACT_BROKER_BASE_URL }}',
                                         'PACT_BROKER_TOKEN' => '${{ secrets.PACT_BROKER_TOKEN }}'))
      expect(level_envs.join).not_to include('PACT_BROKER')
      expect(holders.map { |_name, step| step['run'].to_s }.grep(/secrets\.PACT_BROKER_TOKEN/)).to eq([])
      expect(publish_steps.filter_map { |s| s['run'] }.grep(/\$\{\{/)).to eq([])
      expect(step_named('pact-publish', %r{actions/checkout})['with']).to include('persist-credentials' => false,
                                                                                  'fetch-depth' => 0)
    end

    it 'runs in the pact-broker environment, which no other job uses, with no pull_request_target trigger',
       requirement: 'the-broker-token-reaches-only-the-publish-steps',
       scenario: 'the-publish-job-runs-in-the-pact-broker-environment' do
      name_of = ->(j) { j['environment'].is_a?(Hash) ? j['environment']['name'] : j['environment'] }
      users = workflow.fetch('jobs').select { |_name, j| name_of.call(j) == 'pact-broker' }.keys

      expect(name_of.call(job('pact-publish'))).to eq('pact-broker')
      expect(users).to eq(['pact-publish'])
      expect(workflow['on'].keys).not_to include('pull_request_target')
    end

    it 'passes the broker settings to pact-cli by name, read-only and without verbose output',
       requirement: 'the-broker-token-reaches-only-the-publish-steps',
       scenario: 'the-token-reaches-the-container-by-name-only' do
      dockers = publish_steps.select { |s| broker_step?(s) }

      expect(dockers).not_to be_empty
      expect(dockers.map { |s| s['run'] }).to all(include('docker run', '--rm', '-e PACT_BROKER_BASE_URL',
                                                          '-e PACT_BROKER_TOKEN', '-v "$PWD/pacts:/pacts:ro"'))
      expect(dockers.map { |s| s['run'] }.grep(/-e PACT_BROKER_\w+=/)).to eq([])
      expect(dockers.map { |s| broker_command(s) }.grep(/(^|\s)(--verbose|-v)(\s|$)/)).to eq([])
    end

    it 'publishes only the greeter-acceptance to greeter-http pact, checked before the token is used',
       requirement: 'the-publish-job-checks-its-inputs-before-using-the-token',
       scenario: 'only-the-greeter-acceptance-to-greeter-http-pact-is-published' do
      valid = { 'greeter-acceptance-greeter-http.json' => pact_document }
      check = publish_steps.index(pact_check_step)
      first_token = publish_steps.index { |s| token_step?(s) }

      expect(run_pact_check(valid).last).to be_success
      extra_output, extra = run_pact_check(valid.merge('extra.json' => pact_document))
      expect([extra.success?, extra_output]).to match([false, include('extra.json')])
      consumer_output, consumer = run_pact_check(valid.transform_values { pact_document(consumer: 'x') })
      expect([consumer.success?, consumer_output]).to match([false, include('consumer')])
      provider_output, provider = run_pact_check(valid.transform_values { pact_document(provider: 'x') })
      expect([provider.success?, provider_output]).to match([false, include('provider')])
      expect([publish_steps.index(pacts_download), check, first_token]).to eq([publish_steps.index(pacts_download),
                                                                               check, first_token].sort)
    end

    it 'stops before the token is used when the broker URL is not https',
       requirement: 'the-publish-job-checks-its-inputs-before-using-the-token',
       scenario: 'a-non-https-broker-url-stops-the-job' do
      valid = { 'greeter-acceptance-greeter-http.json' => pact_document }

      output, status = run_pact_check(valid, url: 'http://broker.example.test')
      expect([status.success?, output]).to match([false, include('PACT_BROKER_BASE_URL')])
      expect(run_pact_check(valid, url: 'https://broker.example.test').last).to be_success
    end

    it 'stops a tag whose name is not v followed by the suite version, before publishing and without the token',
       requirement: 'the-publish-job-checks-its-inputs-before-using-the-token',
       scenario: 'a-tag-that-does-not-match-the-suite-version-stops-the-job' do
      expected = "v#{GreeterAcceptance::VERSION}"
      first_publish = publish_steps.index { |s| broker_step?(s) && s['run'].include?('publish') }

      output, status = run_step(tag_check_step, env: { 'GITHUB_REF_NAME' => 'v0.0.0-nope' }, chdir: root)
      expect([status.success?, output]).to match([false, include('v0.0.0-nope', GreeterAcceptance::VERSION)])
      expect(run_step(tag_check_step, env: { 'GITHUB_REF_NAME' => expected }, chdir: root).last).to be_success
      expect(condition(tag_check_step)).to include(on_tag)
      expect(publish_steps.index(tag_check_step)).to be < first_publish
      expect(token_step?(tag_check_step)).to be(false)
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
