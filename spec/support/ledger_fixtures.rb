# frozen_string_literal: true

# Plain-Ruby builders for the documents the tooling specs pass around. They
# return string-keyed hashes, exactly as the documents look once parsed from
# JSON or YAML.
module LedgerFixtures
  PASSING_ROWS = { 'greeting-happy' => 'passed', 'greeting-count' => 'passed' }.freeze

  # A greeterhq.traceability.v2 document for one channel run.
  def trace_doc(channel:, rows: PASSING_ROWS, **run)
    {
      'schema' => 'greeterhq.traceability.v2',
      'run' => default_run(channel).merge(run.transform_keys(&:to_s)),
      'results' => rows.map { |requirement, status| result_row(requirement, status) }
    }
  end

  def result_row(requirement, status)
    row = {
      'requirement' => requirement,
      'scenario' => "#{requirement}-scenario",
      'status' => status
    }
    row['missing_capabilities'] = ['counting'] if status == 'not_applicable'
    row
  end

  # A greeterhq.deployed.v1 document. Channel entries are keyword arguments:
  #   deployed_doc(cli: { version: 'v0.1.2', sha: 'abc1234' })
  def deployed_doc(environment: 'prod', **channels)
    entries = channels.to_h { |name, entry| [name.to_s, entry.transform_keys(&:to_s)] }
    { 'schema' => 'greeterhq.deployed.v1', 'environment' => environment, 'channels' => entries }
  end

  # The shape of config/environments.yml once parsed.
  def environments_config
    {
      'environments' => {
        'prod' => {
          'ledger_branch' => 'ledger-prod',
          'channels' => {
            'http' => http_target('https://prodapi1.execute-api.eu-west-2.amazonaws.com'),
            'cli' => { 'repo' => 'greeterhq/greeter-cli' }
          }
        },
        'stage' => {
          'ledger_branch' => 'ledger-stage',
          'channels' => {
            'http' => http_target('https://stageapi2.execute-api.eu-west-2.amazonaws.com')
          }
        }
      }
    }
  end

  private

  def default_run(channel)
    {
      'channel' => channel,
      'environment' => 'prod',
      'suite_version' => 'v0.2.0',
      'channel_version' => 'v1.2.3',
      'channel_sha' => 'def4567',
      'core_version' => '0.1.5',
      'verification' => 'verified',
      'recorded_at' => '2026-11-06T12:00:00Z',
      'run_id' => '123456789',
      'released_at' => nil,
      'forced' => nil
    }
  end

  def http_target(base_url)
    {
      'base_url' => base_url,
      'host_pattern' => '\A[a-z0-9]+\.execute-api\.eu-west-2\.amazonaws\.com\z'
    }
  end
end
