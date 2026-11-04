# frozen_string_literal: true

require_relative '../../lib/greeter_acceptance/capabilities'
require_relative '../../lib/greeter_acceptance/trace'

# Suite-wide trace for the channel under test. One per run.
def greeter_trace
  $greeter_trace ||= GreeterAcceptance::Trace.new(channel: driver.channel) # rubocop:disable Style/GlobalVars
end

# 5.1 Capability gating + 5.2 tag-validation safety rail.
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

  greeter_trace.record(
    tag_names: tag_names, status: :not_applicable, missing_capabilities: missing
  )
  skip_this_scenario
end

# Record the pass/fail outcome of a scenario that actually ran.
After do |scenario|
  next if scenario.status == :skipped # already recorded as not_applicable

  status = scenario.failed? ? :failed : :passed
  greeter_trace.record(tag_names: scenario.tags.map(&:name), status: status)
end

at_exit do
  $greeter_trace&.write # rubocop:disable Style/GlobalVars
end
