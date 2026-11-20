# frozen_string_literal: true

require 'yaml'

# The shape of .github/workflows/gate.yml, checked statically: the file is parsed,
# never run. Each example states one scenario of the acceptance-gate requirements
# "The gate is a read-only reusable workflow", "An artifact channel is gated on its
# built artifact" and "A service channel is gated at its stage environment".
RSpec.describe '.github/workflows/gate.yml' do
  let(:path) { File.expand_path('../../.github/workflows/gate.yml', __dir__) }
  let(:workflow) { YAML.safe_load_file(path) }
  let(:steps) { workflow.fetch('jobs').fetch('gate').fetch('steps') }

  def step_named(pattern)
    steps.find { |step| step['name'].to_s.match?(pattern) } || raise("no step named like #{pattern.inspect}")
  end

  def runs
    steps.filter_map { |step| step['run'] }
  end

  it 'is callable from a release workflow and from nothing else',
     requirement: 'the-gate-is-a-read-only-reusable-workflow',
     scenario: 'a-release-workflow-calls-the-gate' do
    expect(workflow['on'].keys).to eq(['workflow_call'])
    expect(workflow['on']['workflow_call']['inputs']).to include('acceptance_ref', 'channel', 'candidate_version',
                                                                 'candidate_sha')
  end

  it 'holds read-only permissions and no secret, ledger-writer token or push',
     requirement: 'the-gate-is-a-read-only-reusable-workflow',
     scenario: 'a-gate-run-leaves-the-ledgers-unchanged' do
    expect(workflow['permissions']).to eq('contents' => 'read')
    expect(workflow['jobs'].values.map { |job| job['permissions'] }.compact).to be_empty
    expect(workflow['on']['workflow_call']).not_to have_key('secrets')
    expect(File.read(path).lines.reject { |line| line.strip.start_with?('#') }.join)
      .not_to match(%r{secrets\.|LEDGER_APP|create-github-app-token|bin/publish|git push})
  end

  it 'downloads the caller\'s artifact and runs cli-release extract on it',
     requirement: 'an-artifact-channel-is-gated-on-its-built-artifact',
     scenario: 'the-gate-receives-the-built-artifact' do
    download = step_named(/Download the candidate artifact/)
    unpack = step_named(/Unpack the candidate/)

    expect(download['uses']).to start_with('actions/download-artifact')
    expect(download['with']['name']).to eq('${{ inputs.artifact_name }}')
    expect(steps.index(download)).to be < steps.index(unpack)
    expect(unpack['run']).to include('bin/cli-release extract --tarball "tmp/artifact/$ARTIFACT_FILE"')
    expect([download, unpack].map { |step| step['if'] }).to all(eq("inputs.channel == 'cli'"))
  end

  it 'lets the exit status of the gate step decide the job result',
     requirement: 'an-artifact-channel-is-gated-on-its-built-artifact',
     scenario: 'the-gate-fails' do
    suite = step_named(/Run the suite against the candidate/)
    verdict = step_named(/Decide the gate/)

    expect([suite, verdict].map { |step| step['continue-on-error'] }).to all(be_nil)
    expect(steps.index(suite)).to be < steps.index(verdict)
    expect(verdict['run'].lines.last.strip).to start_with('bin/gate-verdict')
    expect(verdict['run']).not_to match(/\|\||;\s*true|exit 0/)
  end

  it 'reads the http target for stage from committed configuration, never from an input',
     requirement: 'a-service-channel-is-gated-at-its-stage-environment',
     scenario: 'the-gate-targets-the-stage-environment' do
    inputs = workflow['on']['workflow_call']['inputs']
    target = step_named(/Resolve the target from the committed configuration/)
    suite = step_named(/Run the suite against the candidate/)

    expect(inputs['environment']['default']).to eq('stage')
    expect(inputs.keys.grep(/url|host|target|address/i)).to be_empty
    expect(target['if']).to eq("inputs.channel == 'http'")
    expect(target['run']).to include('bin/resolve')
    expect(suite['env']['GREETER_BASE_URL']).to eq("${{ steps.#{target['id']}.outputs.base_url }}")
  end
end
