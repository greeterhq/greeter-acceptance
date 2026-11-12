# frozen_string_literal: true

module GreeterAcceptance
  class Publisher
    # Everything the publisher accepts from outside is checked here. A channel's
    # result is untrusted data: only an allowlist of fields gets through, every
    # value must match a strict pattern, the result must name the channel it is
    # being recorded for, and nothing in it is ever evaluated. What comes out is a
    # rebuilt copy, never the input.
    module Validation
      TRACE_SCHEMA = 'greeterhq.traceability.v2'

      VERSION = /\Av\d+\.\d+\.\d+\z/
      SHA = /\A[0-9a-f]{7,40}\z/
      SLUG = /\A[a-z0-9-]{1,64}\z/
      TOKEN = /\A[0-9A-Za-z._-]{1,64}\z/
      WORD = /\A[a-z0-9_-]{1,32}\z/
      TIMESTAMP = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/

      STATUSES = %w[passed failed error not_applicable].freeze
      VERIFICATIONS = %w[verified mismatch inconsistent unobserved].freeze

      private

      def clean_result(result, channel)
        bytes = JSON.generate(result).bytesize
        if bytes > @max_result_bytes
          raise Refused,
                "result size #{bytes} bytes exceeds the limit of #{@max_result_bytes}"
        end
        raise Refused, 'a result must be an object with the traceability v2 schema' unless valid_document?(result)

        {
          'schema' => TRACE_SCHEMA, 'run' => clean_run(result['run'], channel),
          'results' => Array(result['results']).map { |row| clean_row(row) }
        }
      end

      def valid_document?(result)
        result.is_a?(Hash) && result['schema'] == TRACE_SCHEMA
      end

      def clean_run(run, channel)
        raise Refused, 'a result must have a run object' unless run.is_a?(Hash)
        raise Refused, "the result names channel '#{run['channel']}', not '#{channel}'" unless run['channel'] == channel

        unless run['environment'] == @environment
          raise Refused, "the result is for environment '#{run['environment']}', not '#{@environment}'"
        end

        { 'channel' => channel, 'environment' => @environment }.merge(run_values(run))
      end

      def run_values(run)
        {
          'suite_version' => field(run, 'suite_version', VERSION),
          'channel_version' => field(run, 'channel_version', VERSION),
          'channel_sha' => field(run, 'channel_sha', SHA),
          'core_version' => field(run, 'core_version', TOKEN),
          'verification' => choice(run, 'verification', VERIFICATIONS),
          'recorded_at' => field(run, 'recorded_at', TIMESTAMP),
          'run_id' => field(run, 'run_id', TOKEN),
          'released_at' => field(run, 'released_at', TIMESTAMP),
          'forced' => nil
        }
      end

      def clean_row(row)
        raise Refused, 'a result row must be an object' unless row.is_a?(Hash)

        clean = {
          'requirement' => required(row, 'requirement', SLUG), 'scenario' => required(row, 'scenario', SLUG),
          'status' => choice(row, 'status', STATUSES, nullable: false)
        }
        clean['missing_capabilities'] = capabilities(row['missing_capabilities']) if row.key?('missing_capabilities')
        clean
      end

      def capabilities(list)
        raise Refused, 'missing_capabilities must be a list' unless list.is_a?(Array)

        list.map do |name|
          raise Refused, "capability #{name.inspect} is not a valid name" unless name.is_a?(String) && WORD.match?(name)

          name
        end
      end

      def clean_deployment(deployment)
        version = deployment['version']
        raise Refused, "version #{version.inspect} is not a semantic version like v1.2.3" unless matches?(version,
                                                                                                          VERSION)

        {
          'version' => version, 'sha' => required(deployment, 'sha', SHA),
          'run_id' => field(deployment, 'run_id', TOKEN), 'artifact' => field(deployment, 'artifact', WORD)
        }
      end

      def field(source, key, pattern)
        value = source[key]
        return nil if value.nil?
        raise Refused, "#{key} #{value.inspect} is not valid" unless matches?(value, pattern)

        value
      end

      def required(source, key, pattern)
        value = source[key]
        raise Refused, "#{key} #{value.inspect} is not a valid name" unless matches?(value, pattern)

        value
      end

      def choice(source, key, allowed, nullable: true)
        value = source[key]
        return nil if value.nil? && nullable
        return value if allowed.include?(value)

        raise Refused, "#{key} #{value.inspect} is not one of #{allowed.join(', ')}"
      end

      def matches?(value, pattern)
        value.is_a?(String) && pattern.match?(value)
      end

      def semantic(version)
        Gem::Version.new(version.delete_prefix('v'))
      end
    end
  end
end
