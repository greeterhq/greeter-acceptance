# frozen_string_literal: true

require_relative '../../lib/greeter_acceptance/capabilities'
require_relative '../../lib/greeter_acceptance/composition_root'
require_relative '../../lib/greeter_acceptance/run_record'
require_relative '../../lib/greeter_acceptance/version'

TRACE_PATH = 'tmp/traceability.json'

# The record of this run. One per process: each scenario gets a World (and a
# driver) of its own, so anything the run learns has to be kept out here.
module GreeterAcceptance
  class << self
    attr_accessor :run_record
  end
end

# Start the run record before any scenario: read what the run is about from the
# environment, and probe the channel once for the version it reports. A missing
# or unknown GREETER_CHANNEL stops the run here with a clear message.
BeforeAll do
  env = ENV
  probe = GreeterAcceptance::CompositionRoot.build_driver(env: env)

  record = GreeterAcceptance::RunRecord.new(
    channel: probe.channel,
    environment: env.fetch('GREETER_ENVIRONMENT', 'local'),
    suite_version: "v#{GreeterAcceptance::VERSION}",
    expected_version: env.fetch('GREETER_EXPECTED_VERSION', nil),
    expected_sha: env.fetch('GREETER_EXPECTED_SHA', nil),
    run_id: env.fetch('GITHUB_RUN_ID') { env.fetch('GREETER_RUN_ID', nil) },
    released_at: env.fetch('GREETER_RELEASED_AT', nil)
  )
  record.observe(probe.build_info)
  GreeterAcceptance.run_record = record
end

# Capability gating + the tag-validation safety rail.
#
# Before each scenario, first validate its @capability-* tags against the known
# capability set: an unknown tag (e.g. a typo @capability-countng) raises and
# aborts the run, naming the offending tag, so it can never silently run on a
# channel that lacks the misspelled capability.
#
# Then gate: if the active channel lacks any required capability, record the
# whole scenario as not_applicable (with its missing capabilities) and skip its
# steps. A gated scenario is never failed or silently skipped.
Before do |scenario|
  tag_names = scenario.tags.map(&:name)

  required = GreeterAcceptance::Capabilities.required_from_tags(tag_names)

  unknown = required.reject { |cap| GreeterAcceptance::Capabilities.known?(cap) }
  unless unknown.empty?
    raise "Unknown capability tag(s): #{unknown.map { |c| "@capability-#{c}" }.join(', ')}. " \
          "Known capabilities: #{GreeterAcceptance::Capabilities::KNOWN.to_a.join(', ')}."
  end

  missing = required.reject { |cap| driver.supports?(cap) }
  next if missing.empty?

  GreeterAcceptance.run_record.row(
    tag_names: tag_names, status: :not_applicable, missing_capabilities: missing
  )
  skip_this_scenario
end

# Record the outcome of a scenario that actually ran. An infrastructure error the
# driver reported wins over a failed assertion, so a channel outage is `error`,
# not `failed`. The version the channel reported during the scenario is observed
# too, so a version that changes mid-run is caught.
After do |scenario|
  next if scenario.status == :skipped # already recorded as not_applicable

  record = GreeterAcceptance.run_record
  record.observe(driver.build_info)
  status = GreeterAcceptance::RunRecord.status_for(
    failed: scenario.failed?, infrastructure_error: driver.infrastructure_error?
  )
  record.row(tag_names: scenario.tags.map(&:name), status: status)
end

AfterAll do
  GreeterAcceptance.run_record&.write(TRACE_PATH)
end
