# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module GreeterAcceptance
  # The record of one run against one channel: one row per scenario, plus the
  # context that says exactly what was tested (suite version, channel version,
  # core version, environment, when, which run) and whether the channel's own
  # reported version could be verified. Written as greeterhq.traceability.v2.
  #
  # One instance per process. It outlives the per-scenario World objects, which
  # is why the hooks feed it rather than the drivers keeping the state.
  class RunRecord
    SCHEMA = 'greeterhq.traceability.v2'

    REQUIREMENT_TAG = /\A@requirement-(.+)\z/
    SCENARIO_TAG = /\A@scenario-(.+)\z/

    # An infrastructure error wins over a failed assertion: when the channel
    # itself was unreachable or misbehaved, the scenario did not get a fair run.
    def self.status_for(failed:, infrastructure_error:)
      return :error if infrastructure_error

      failed ? :failed : :passed
    end

    def initialize(channel:, environment:, suite_version:, expected_version: nil, expected_sha: nil,
                   run_id: nil, released_at: nil, clock: Time)
      @channel = channel
      @environment = environment
      @suite_version = suite_version
      # Optional context comes from the environment, where an unset CI step output
      # arrives as an empty string. Empty means unknown, and is recorded as null.
      @expected_version = presence(expected_version)
      @expected_sha = presence(expected_sha)
      @run_id = presence(run_id)
      @released_at = presence(released_at)
      @clock = clock
      @rows = []
      @observations = []
    end

    # status: :passed | :failed | :error | :not_applicable
    def row(tag_names:, status:, missing_capabilities: [])
      entry = {
        'requirement' => slug_from(tag_names, REQUIREMENT_TAG),
        'scenario' => slug_from(tag_names, SCENARIO_TAG),
        'status' => status.to_s
      }
      entry['missing_capabilities'] = missing_capabilities.map(&:to_s) if status == :not_applicable
      @rows << entry
    end

    # An unobservable (nil) build information is ignored.
    def observe(build_info)
      @observations << build_info unless build_info.nil?
    end

    # verified     every observation equals the expected version
    # mismatch     the observed version differs from the expected one
    # inconsistent two different versions were observed during the run
    # unobserved   nothing was observed, or there is no expected version to
    #              compare it with (so the run cannot be reported as verified)
    def verification
      versions = observed_versions
      return :unobserved if versions.empty?
      return :inconsistent if versions.size > 1
      return :unobserved if @expected_version.nil?

      versions.first == canonical(@expected_version) ? :verified : :mismatch
    end

    def document
      { 'schema' => SCHEMA, 'run' => run_context, 'results' => @rows.map(&:dup) }
    end

    def write(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{JSON.pretty_generate(document)}\n")
      path
    end

    private

    def run_context
      {
        'channel' => @channel.to_s, 'environment' => @environment, 'suite_version' => @suite_version,
        'channel_version' => attributed_version, 'channel_sha' => @expected_sha,
        'core_version' => observed_core_version, 'verification' => verification.to_s,
        'recorded_at' => @clock.now.utc.iso8601, 'run_id' => @run_id,
        'released_at' => @released_at, 'forced' => nil
      }
    end

    # The version the results are attributed to: what was actually observed when
    # that is unambiguous, so a mismatched run is never attributed to the version
    # it was expected to test. With nothing observed, the claimed version is
    # recorded and the run is marked unobserved. Two versions cannot be attributed.
    def attributed_version
      versions = observed_versions
      return versions.first if versions.size == 1
      return nil if versions.size > 1

      canonical(@expected_version)
    end

    def observed_core_version
      @observations.first&.core_version if observed_versions.size == 1
    end

    def observed_versions
      @observations.map { |info| canonical(info.channel_version) }.compact.uniq
    end

    # Versions are compared and recorded with a leading v ("1.2.3" == "v1.2.3"):
    # greeter-cli prints 0.1.2 while its release tag is v0.1.2.
    def canonical(version)
      return nil if version.nil? || version.to_s.empty?

      "v#{version.to_s.delete_prefix('v')}"
    end

    def slug_from(tag_names, pattern)
      tag_names.each do |tag|
        match = pattern.match(tag)
        return match[1] if match
      end
      nil
    end

    def presence(value)
      text = value&.to_s
      text unless text.nil? || text.strip.empty?
    end
  end
end
