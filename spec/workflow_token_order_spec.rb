# frozen_string_literal: true

require 'yaml'

# harden-candidate-install: in each workflow job, no step that references a token
# or secret runs after the first step that runs candidate code (design.md, "The
# ordering spec"). `bin/cli-release install` evaluates the candidate's Gemfile, so
# it marks the boundary.
module TokenOrder
  TOKEN_REFERENCE = /secrets\.|github\.token|steps\.[\w-]+\.outputs\.token/
  WORKFLOWS = {
    'record.yml' => File.expand_path('../.github/workflows/record.yml', __dir__),
    'gate.yml' => File.expand_path('../.github/workflows/gate.yml', __dir__)
  }.freeze

  module_function

  def steps_by_job(path)
    YAML.safe_load_file(path).fetch('jobs').transform_values { |job| job.fetch('steps', []) }
  end

  def install_step?(step)
    step['run'].to_s.include?('bin/cli-release install')
  end

  def label(step)
    step['name'] || step['id'] || step['uses'] || step['run'].to_s.lines.first.to_s.strip
  end

  def candidate_jobs(path)
    steps_by_job(path).select { |_job, steps| steps.any? { |step| install_step?(step) } }
  end

  def token_reference?(step)
    %w[env with run].any? { |key| step[key].to_s.match?(TOKEN_REFERENCE) }
  end

  # "<job>: <step>" for each step after the job's first candidate install that
  # references a token.
  def offenders(path)
    candidate_jobs(path).flat_map do |job, steps|
      boundary = steps.index { |step| install_step?(step) }
      steps.drop(boundary + 1).select { |step| token_reference?(step) }.map { |step| "#{job}: #{label(step)}" }
    end
  end
end

RSpec.describe 'workflow token order' do
  TokenOrder::WORKFLOWS.each do |file, path|
    describe file do
      it 'has at least one job that installs a candidate' do
        expect(TokenOrder.candidate_jobs(path)).not_to be_empty
      end

      it 'has no step after the first candidate install that references a token' do
        offenders = TokenOrder.offenders(path)

        expect(offenders).to be_empty,
                             "steps that reference a token after the candidate install: #{offenders.join('; ')}"
      end
    end
  end

  describe 'record.yml' do
    let(:names) { TokenOrder.steps_by_job(TokenOrder::WORKFLOWS.fetch('record.yml')).fetch('run').map { |step| step['name'] } }

    it 'looks up when the release was published before it fetches the release' do
      lookup = names.index('Look up when the release was published')
      fetch = names.index('Fetch the release (checksum and tag checked)')

      expect([lookup, fetch]).not_to include(nil)
      expect(lookup).to be < fetch
    end
  end
end
