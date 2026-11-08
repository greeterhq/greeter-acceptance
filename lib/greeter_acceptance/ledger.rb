# frozen_string_literal: true

module GreeterAcceptance
  # Derives the cross-channel ledger (greeterhq.ledger.v2) from the per-channel
  # results and the deployed record: a requirement-by-channel matrix, plus a
  # column per channel saying whether its result is current, stale or missing.
  #
  # The ledger is a pure function of its inputs. It carries no timestamp of its
  # own and every collection is sorted, so regenerating it from the same records
  # gives identical output whatever order they arrive in.
  class Ledger
    SCHEMA = 'greeterhq.ledger.v2'

    # Worst first, so a requirement with several scenarios shows its worst result.
    STATUS_PRECEDENCE = %w[error failed passed not_applicable].freeze

    # The requirement slugs the suite defines: every @requirement-<slug> tag in
    # the feature files under dir.
    def self.requirements_from_features(dir)
      Dir.glob(File.join(dir, '**', '*.feature')).flat_map do |file|
        File.read(file).scan(/@requirement-([a-z0-9-]+)/).flatten
      end.uniq.sort
    end

    # channels:     every channel the ledger has a column for
    # requirements: every requirement the suite defines
    # results:      channel => greeterhq.traceability.v2 document, or nil
    # deployed:     greeterhq.deployed.v1 document
    def self.build(**inputs)
      new(**inputs).document
    end

    def initialize(environment:, suite_version:, channels:, requirements:, results:, deployed:)
      @environment = environment
      @suite_version = suite_version
      @channels = channels.sort
      @requirements = requirements.sort
      @results = results
      @deployed = deployed
    end

    def document
      {
        'schema' => SCHEMA, 'environment' => @environment, 'suite' => { 'version' => @suite_version },
        'channels' => @channels.to_h { |channel| [channel, column(channel)] },
        'requirements' => @requirements.to_h { |requirement| [requirement, cells(requirement)] }
      }
    end

    private

    def column(channel)
      result = @results[channel]
      return { 'state' => 'missing', 'reasons' => [] } if result.nil?

      run = result.fetch('run')
      reasons = stale_reasons(channel, run)
      {
        'state' => reasons.empty? ? 'current' : 'stale', 'reasons' => reasons,
        'channel_version' => run['channel_version'], 'core_version' => run['core_version'],
        'suite_version' => run['suite_version'], 'verification' => run['verification'],
        'recorded_at' => run['recorded_at'], 'run_id' => run['run_id']
      }
    end

    def stale_reasons(channel, run)
      reasons = []
      reasons << 'channel' if deployed_moved_on?(channel, run)
      reasons << 'suite' if older_suite?(run)
      reasons
    end

    def deployed_moved_on?(channel, run)
      recorded = @deployed.dig('channels', channel)
      !recorded.nil? && canonical(recorded['version']) != canonical(run['channel_version'])
    end

    def older_suite?(run)
      version(run['suite_version']) < version(@suite_version)
    end

    # An unparseable or missing version cannot be shown to be current, so it
    # sorts before every real one.
    def version(text)
      Gem::Version.new(text.to_s.delete_prefix('v'))
    rescue ArgumentError
      Gem::Version.new('0')
    end

    def canonical(text)
      text.nil? ? nil : "v#{text.to_s.delete_prefix('v')}"
    end

    def cells(requirement)
      @channels.to_h { |channel| [channel, status_of(requirement, @results[channel])] }
    end

    def status_of(requirement, result)
      return 'missing' if result.nil?

      statuses = result.fetch('results').select { |row| row['requirement'] == requirement }.map { |row| row['status'] }
      STATUS_PRECEDENCE.find { |status| statuses.include?(status) } || 'missing'
    end
  end
end
