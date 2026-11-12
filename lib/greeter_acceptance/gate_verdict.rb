# frozen_string_literal: true

module GreeterAcceptance
  # Decides whether a gate run passes, from the trace the run wrote. A gate judges
  # the candidate on its own: it fails on any failed or errored scenario, on a
  # version that does not match the candidate (or changed during the run), and on a
  # version it could not observe unless the caller explicitly allows an unverified
  # run. Scenarios that are not applicable never fail it.
  module GateVerdict
    Verdict = Struct.new(:reasons, :unverified, keyword_init: true) do
      def passed?
        reasons.empty?
      end

      def unverified?
        unverified
      end
    end

    BAD_STATUSES = %w[failed error].freeze

    module_function

    def evaluate(trace, acceptance_ref:, expected_version: nil, allow_unverified: false)
      run = trace.fetch('run')
      unverified = run['verification'] == 'unobserved'
      if acceptance_ref.to_s.empty?
        return Verdict.new(reasons: ['no acceptance reference was supplied; the gate needs the suite version to run'],
                           unverified: unverified)
      end

      reasons = row_reasons(trace) + version_reasons(run, expected_version, allow_unverified)
      Verdict.new(reasons: reasons, unverified: unverified)
    end

    def row_reasons(trace)
      trace.fetch('results').select { |row| BAD_STATUSES.include?(row['status']) }
           .map { |row| "#{row['requirement']} #{row['status']}" }
    end

    def version_reasons(run, expected_version, allow_unverified)
      case run['verification']
      when 'verified' then []
      when 'mismatch'
        ["the channel reported version #{run['channel_version']}, not the candidate #{expected_version}"]
      when 'inconsistent' then ['the channel reported different versions during the run']
      else
        allow_unverified ? [] : ['the channel version could not be observed']
      end
    end
  end
end
