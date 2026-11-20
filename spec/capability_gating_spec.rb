# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# The capability gate in features/support/hooks.rb, exercised by running Cucumber
# as a subprocess over fixture features, against a fake greeter CLI (the cli
# channel declares no capabilities).
#
# The hooks write tmp/traceability.json relative to the working directory and the
# path is a constant, so Cucumber runs from a scratch copy of lib/ and
# features/support/. The repository's own tmp/traceability.json is never touched.
RSpec.describe 'capability gating' do
  let(:repo_root) { File.expand_path('..', __dir__) }
  let(:fixtures) { File.join(repo_root, 'spec/fixtures/capability_gating') }
  let(:project) { Dir.mktmpdir('capability-gating') }
  let(:markers) { File.join(project, 'markers') }

  before do
    FileUtils.mkdir_p([markers, File.join(project, 'features')])
    FileUtils.cp_r(File.join(repo_root, 'lib'), File.join(project, 'lib'))
    FileUtils.cp_r(File.join(repo_root, 'features/support'), File.join(project, 'features/support'))
    FileUtils.cp_r(Dir[File.join(fixtures, 'features/*')], File.join(project, 'features'))
  end

  after { FileUtils.remove_entry(project) }

  # Runs `bundle exec cucumber` on one fixture feature. The suite's own bundle is
  # inherited from the environment, so nothing is installed or locked.
  def cucumber(feature)
    env = { 'GREETER_CHANNEL' => 'cli', 'GREETER_CLI_CMD' => File.join(repo_root, 'spec/fixtures/bin/fake_greeter'),
            'GATING_MARKER_DIR' => markers, 'GREETER_ENVIRONMENT' => nil, 'GREETER_EXPECTED_VERSION' => nil,
            'GREETER_EXPECTED_SHA' => nil, 'GITHUB_RUN_ID' => nil, 'GREETER_RUN_ID' => nil,
            'CUCUMBER_PUBLISH_QUIET' => 'true' }
    Open3.capture2e(env, 'bundle', 'exec', 'cucumber', "features/#{feature}.feature", '--require', 'features',
                    '--format', 'pretty', chdir: project)
  end

  def rows
    JSON.parse(File.read(File.join(project, 'tmp/traceability.json'))).fetch('results')
  end

  it 'records a scenario that needs a missing capability as not applicable and runs none of its steps',
     requirement: 'a-scenario-is-gated-by-its-capability-tags',
     scenario: 'a-capability-tagged-scenario-on-a-channel-without-the-capability' do
    output, status = cucumber('gated')

    expect(status.exitstatus).to eq(0), output
    expect(rows).to include(
      { 'requirement' => 'fixture-gated', 'scenario' => 'fixture-gated', 'status' => 'not_applicable',
        'missing_capabilities' => ['counting'] }
    )
    expect(File.exist?(File.join(markers, 'gated'))).to be(false)
  end

  # Not tagged to a scenario of the requirement: the cli channel has no capability, so
  # this shows only that gating leaves an untagged scenario alone. A scenario that needs a
  # capability the channel does have is not exercised here.
  it 'runs a scenario with no capability tag and records it as passed' do
    output, status = cucumber('gated')

    expect(status.exitstatus).to eq(0), output
    expect(rows).to include({ 'requirement' => 'fixture-plain', 'scenario' => 'fixture-plain', 'status' => 'passed' })
    expect(File.exist?(File.join(markers, 'plain'))).to be(true)
  end

  it 'stops on a capability tag the suite does not know and names it',
     requirement: 'every-capability-tag-names-a-known-capability',
     scenario: 'an-unknown-capability-tag-halts-the-run' do
    output, status = cucumber('typo')

    expect(status.exitstatus).not_to eq(0)
    expect(output).to include('Unknown capability tag(s)').and include('@capability-countng')
    expect(File.exist?(File.join(markers, 'typo'))).to be(false)
  end

  it 'leaves the repository tmp/traceability.json alone' do
    path = File.join(repo_root, 'tmp/traceability.json')
    before_bytes = File.exist?(path) ? File.binread(path) : nil

    cucumber('gated')

    expect(File.exist?(path) ? File.binread(path) : nil).to eq(before_bytes)
  end
end
