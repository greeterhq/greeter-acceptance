# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# adopt-live-docs: bin/merge-repo-trace merges any number of greeterhq.repo-trace.v1
# files into one, the way the CI `trace` job calls it:
#
#   ruby bin/merge-repo-trace OUT IN...
#
# On any problem it exits 1 with one message on stderr and writes nothing.
RSpec.describe 'bin/merge-repo-trace' do
  let(:script) { File.expand_path('../../bin/merge-repo-trace', __dir__) }
  let(:dir) { Dir.mktmpdir('merge-repo-trace') }
  let(:out) { File.join(dir, 'merged.json') }
  let(:spec_trace) do
    write_trace('spec.json', document(recorded_at: '2026-11-20T10:00:00Z',
                                      results: [result(requirement: 'req-b', location: 'spec/b_spec.rb:2')]))
  end
  let(:cli_trace) do
    write_trace('cli.json', document(recorded_at: '2026-11-20T10:05:00Z',
                                     results: [result(requirement: 'req-a',
                                                      location: 'spec/drivers/cli_driver_spec.rb:9')]))
  end
  let(:http_trace) do
    write_trace('http.json', document(recorded_at: '2026-11-20T10:03:00Z',
                                      results: [result(requirement: 'req-a',
                                                       location: 'spec/drivers/http_driver_spec.rb:9')]))
  end

  after { FileUtils.remove_entry(dir) }

  def result(requirement:, location:, scenario: 'a-scenario', status: 'passed')
    { 'requirement' => requirement, 'scenario' => scenario, 'status' => status, 'source' => 'rspec',
      'location' => location }
  end

  def document(results:, **overrides)
    {
      'schema' => 'greeterhq.repo-trace.v1', 'repo' => 'greeter-acceptance',
      'sha' => '0123456789abcdef0123456789abcdef01234567', 'recorded_at' => '2026-11-20T10:00:00Z',
      'run_id' => '987654321', 'results' => results
    }.merge(overrides.transform_keys(&:to_s))
  end

  def write_trace(name, doc)
    path = File.join(dir, name)
    File.write(path, JSON.generate(doc))
    path
  end

  def merge(*inputs)
    Open3.capture3(RbConfig.ruby, script, out, *inputs)
  end

  # The field name as a whole word, so the script's own path (merge-repo-trace)
  # does not satisfy it.
  def field_name(field)
    /(?<![\w-])#{field}(?![\w-])/
  end

  it 'combines every input: shared fields, the latest recorded_at and all results sorted',
     requirement: 'per-job-traces-merge-into-one-trace', scenario: 'merge-combines-all-traces' do
    _stdout, stderr, status = merge(spec_trace, cli_trace, http_trace)

    expect([status.exitstatus, stderr]).to eq([0, ''])
    merged = JSON.parse(File.read(out))
    expect(merged).to include('schema' => 'greeterhq.repo-trace.v1', 'repo' => 'greeter-acceptance',
                              'run_id' => '987654321', 'recorded_at' => '2026-11-20T10:05:00Z')
    expect(merged['results'].map { |r| r['location'] }).to eq(
      %w[spec/b_spec.rb:2 spec/drivers/cli_driver_spec.rb:9 spec/drivers/http_driver_spec.rb:9]
    )
  end

  %w[schema repo sha run_id].each do |field|
    it "refuses inputs that differ in #{field}, names the field and writes no output file",
       requirement: 'per-job-traces-merge-into-one-trace', scenario: 'merge-rejects-mismatched-inputs' do
      other = { 'schema' => 'greeterhq.repo-trace.v1', 'repo' => 'greeter-core',
                'sha' => 'fedcba9876543210fedcba9876543210fedcba98', 'run_id' => '111' }
      odd = write_trace('odd.json', document(results: [result(requirement: 'req-z', location: 'spec/z_spec.rb:1')],
                                             field => other.fetch(field, 'greeterhq.repo-trace.v2')))
      _stdout, stderr, status = merge(spec_trace, cli_trace, odd)

      expect(status.exitstatus).to eq(1)
      expect(stderr).to match(field_name(field))
      expect(File.exist?(out)).to be(false)
    end
  end

  it 'refuses a null run_id against a value and names run_id',
     requirement: 'per-job-traces-merge-into-one-trace', scenario: 'merge-rejects-mismatched-inputs' do
    no_run = write_trace('no_run.json', document(run_id: nil, results: [result(requirement: 'req-z',
                                                                               location: 'spec/z_spec.rb:1')]))
    _stdout, stderr, status = merge(spec_trace, no_run)

    expect([status.exitstatus, stderr]).to match([1, a_string_including('run_id')])
    expect(File.exist?(out)).to be(false)
  end

  {
    'an unknown top-level key' => [{ 'extra' => 'x' }, 'extra'],
    'a status outside passed, failed, pending and skipped' => [
      { 'results' => [{ 'requirement' => 'r', 'scenario' => 's', 'status' => 'error', 'source' => 'rspec',
                        'location' => 'spec/a_spec.rb:1' }] }, 'status'
    ],
    'a source other than rspec' => [
      { 'results' => [{ 'requirement' => 'r', 'scenario' => 's', 'status' => 'passed', 'source' => 'cucumber',
                        'location' => 'spec/a_spec.rb:1' }] }, 'source'
    ],
    'a result with an extra key' => [
      { 'results' => [{ 'requirement' => 'r', 'scenario' => 's', 'status' => 'passed', 'source' => 'rspec',
                        'location' => 'spec/a_spec.rb:1', 'description' => 'Alice Smith' }] }, 'description'
    ],
    'a requirement that is not a slug' => [
      { 'results' => [{ 'requirement' => 'Alice Smith', 'scenario' => 's', 'status' => 'passed',
                        'source' => 'rspec', 'location' => 'spec/a_spec.rb:1' }] }, 'requirement'
    ],
    'a location outside spec/' => [
      { 'results' => [{ 'requirement' => 'r', 'scenario' => 's', 'status' => 'passed', 'source' => 'rspec',
                        'location' => '../etc/passwd:1' }] }, 'location'
    ]
  }.each do |description, (override, field)|
    it "refuses an input with #{description}, names the file and field and writes no output file",
       requirement: 'per-job-traces-merge-into-one-trace', scenario: 'merge-rejects-inputs-outside-the-v1-shape' do
      bad = write_trace('bad.json', document(results: [result(requirement: 'req-z', location: 'spec/z_spec.rb:1')])
                                      .merge(override))
      _stdout, stderr, status = merge(spec_trace, bad)

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include('bad.json').and match(field_name(field))
      expect(stderr).not_to include('Alice Smith')
      expect(File.exist?(out)).to be(false)
    end
  end

  it 'refuses a result that appears in two inputs and names its requirement and location',
     requirement: 'per-job-traces-merge-into-one-trace', scenario: 'merge-rejects-a-duplicated-result' do
    twin = write_trace('twin.json', document(results: [result(requirement: 'req-b', location: 'spec/b_spec.rb:2')]))
    _stdout, stderr, status = merge(spec_trace, twin)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('req-b').and include('spec/b_spec.rb:2')
    expect(File.exist?(out)).to be(false)
  end
end
