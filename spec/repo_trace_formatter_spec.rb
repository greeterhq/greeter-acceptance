# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# adopt-live-docs: RepoTraceFormatter writes a greeterhq.repo-trace.v1 file with one
# result per example tagged with both `requirement` and `scenario`. It reads only
# slug metadata, status and location, never descriptions or failure messages.
#
# Each example runs fixture example files in a subprocess (the formatter is
# selected with --format) and reads the JSON it wrote.
RSpec.describe 'RepoTraceFormatter' do
  let(:repo_root) { File.expand_path('..', __dir__) }
  let(:fixtures) { File.join(repo_root, 'spec/fixtures/repo_trace') }
  let(:sha) { '0123456789abcdef0123456789abcdef01234567' }
  let(:run_log) { [] }
  let(:project) { Dir.mktmpdir('repo-trace-formatter') }
  let(:trace_path) { File.join(project, 'out', 'trace.json') }

  before do
    FileUtils.mkdir_p(File.join(project, 'spec/fixtures'))
    FileUtils.cp_r(fixtures, File.join(project, 'spec/fixtures/repo_trace'))
  end

  after { FileUtils.remove_entry(project) }

  # Runs rspec on the fixture files with the formatter, from a scratch project
  # whose layout matches the repository's (so locations read spec/fixtures/...).
  def run_rspec(*files, env: {}, cwd: project)
    command = [RbConfig.ruby, Gem.bin_path('rspec-core', 'rspec'), '--options', '/dev/null',
               '--require', File.expand_path('support/repo_trace_formatter.rb', __dir__),
               '--format', 'RepoTraceFormatter', *files.map { |file| "spec/fixtures/repo_trace/#{file}" }]
    output, status = Open3.capture2e(base_env.merge(env), *command, chdir: cwd)
    run_log.replace([output])
    [output, status]
  end

  def base_env
    { 'REPO_TRACE_PATH' => trace_path, 'GITHUB_SHA' => sha, 'GITHUB_RUN_ID' => '987654321' }
  end

  # A failure message that names what rspec said without printing all of it.
  def first_line(output)
    "expected the formatter to report the field; rspec said: #{output.lines.first.to_s.strip}"
  end

  def trace
    unless File.exist?(trace_path)
      raise "no trace file at #{trace_path}; rspec said: #{run_log.first.to_s.lines.first(2).join}"
    end

    JSON.parse(File.read(trace_path))
  end

  def line_of(file, text)
    File.readlines(File.join(fixtures, file)).index { |line| line.include?(text) } + 1
  end

  it 'writes the v1 document with one result per tagged example',
     requirement: 'repo-trace-contains-only-slugs-statuses-locations-and-run-metadata',
     scenario: 'formatter-writes-the-v1-document' do
    run_rspec('statuses.rb')

    expect(trace).to include('schema' => 'greeterhq.repo-trace.v1', 'repo' => 'greeter-acceptance',
                             'sha' => sha, 'run_id' => '987654321')
    expect(trace['recorded_at']).to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/)
    expect(trace['results']).to eq(
      [
        { 'requirement' => 'a-requirement', 'scenario' => 'a-scenario', 'status' => 'passed', 'source' => 'rspec',
          'location' => "spec/fixtures/repo_trace/statuses.rb:#{line_of('statuses.rb', "it 'passes'")}" },
        { 'requirement' => 'a-requirement', 'scenario' => 'another-scenario', 'status' => 'failed',
          'source' => 'rspec',
          'location' => "spec/fixtures/repo_trace/statuses.rb:#{line_of('statuses.rb', "it 'fails'")}" }
      ]
    )
  end

  it 'takes the sha from git and a missing run id as null when the environment gives neither',
     requirement: 'repo-trace-contains-only-slugs-statuses-locations-and-run-metadata',
     scenario: 'formatter-writes-the-v1-document' do
    run_rspec('statuses.rb', env: { 'GITHUB_SHA' => nil, 'GITHUB_RUN_ID' => nil }, cwd: repo_root)

    expect(trace).to include('sha' => `git -C #{repo_root} rev-parse HEAD`.strip, 'run_id' => nil)
  end

  it 'tells skipped from pending',
     requirement: 'repo-trace-contains-only-slugs-statuses-locations-and-run-metadata',
     scenario: 'formatter-tells-skipped-from-pending' do
    run_rspec('skip_pending.rb')

    statuses = trace['results'].to_h { |result| [result['scenario'], result['status']] }
    expect(statuses).to eq('skipped-scenario' => 'skipped', 'pending-scenario' => 'pending')
  end

  it 'refuses a requirement that is not a slug, names the field and writes no file',
     requirement: 'repo-trace-contains-only-slugs-statuses-locations-and-run-metadata',
     scenario: 'formatter-refuses-malformed-values' do
    output, = run_rspec('malformed_requirement.rb')

    expect(output.include?('invalid requirement')).to be(true), first_line(output)
    expect(output).not_to include('Alice Smith')
    expect(File.exist?(trace_path)).to be(false)
  end

  it 'refuses a sha or run id that does not match its pattern, names the field and writes no file',
     requirement: 'repo-trace-contains-only-slugs-statuses-locations-and-run-metadata',
     scenario: 'formatter-refuses-malformed-values' do
    sha_output, = run_rspec('statuses.rb', env: { 'GITHUB_SHA' => 'not-a-sha' })
    sha_written = File.exist?(trace_path)
    run_output, = run_rspec('statuses.rb', env: { 'GITHUB_RUN_ID' => '12; rm -rf /' })

    expect(sha_output.include?('invalid sha')).to be(true), first_line(sha_output)
    expect(run_output.include?('invalid run_id')).to be(true), first_line(run_output)
    expect([sha_written, File.exist?(trace_path)]).to eq([false, false])
  end

  it 'omits descriptions and failure messages: only the five result keys are written',
     requirement: 'repo-trace-contains-only-slugs-statuses-locations-and-run-metadata',
     scenario: 'formatter-omits-descriptions' do
    run_rspec('privacy.rb')

    expect(File.read(trace_path)).not_to include('Alice Smith')
    expect(File.read(trace_path)).not_to include('Bob Jones')
    expect(trace['results'].map { |result| result.keys.sort }.uniq).to eq(
      [%w[location requirement scenario source status]]
    )
  end

  it 'leaves tmp/traceability.json alone and writes the default path when REPO_TRACE_PATH is unset',
     requirement: 'repo-trace-contains-only-slugs-statuses-locations-and-run-metadata',
     scenario: 'formatter-leaves-the-per-channel-run-file-alone' do
    run_file = File.join(project, 'tmp/traceability.json')
    FileUtils.mkdir_p(File.dirname(run_file))
    File.write(run_file, %({"schema":"greeterhq.traceability.v2"}\n))

    run_rspec('statuses.rb', env: { 'REPO_TRACE_PATH' => nil })

    expect(File.read(run_file)).to eq(%({"schema":"greeterhq.traceability.v2"}\n))
    expect(JSON.parse(File.read(File.join(project, 'tmp/repo-trace.json')))).to include('repo' => 'greeter-acceptance')
  end

  it 'locates a shared example at the line that included it, so two inclusions do not collide',
     requirement: 'shared-example-results-are-located-at-their-inclusion',
     scenario: 'two-inclusions-of-one-shared-example-do-not-collide' do
    run_rspec('including_a.rb', 'including_b.rb')

    expect(trace['results'].map { |result| result.values_at('requirement', 'scenario', 'status', 'location') }).to eq(
      [
        ['a-requirement', 'a-scenario', 'failed',
         "spec/fixtures/repo_trace/including_a.rb:#{line_of('including_a.rb', 'it_behaves_like')}"],
        ['a-requirement', 'a-scenario', 'failed',
         "spec/fixtures/repo_trace/including_b.rb:#{line_of('including_b.rb', 'it_behaves_like')}"]
      ]
    )
  end
end
