# frozen_string_literal: true

require_relative '../../lib/greeter_acceptance/composition_root'

# The Cucumber World. It does not construct a driver itself: the composition
# root (lib/greeter_acceptance/composition_root.rb) is the only place that does,
# and picks the adapter from GREETER_CHANNEL (cli|http). This file only exposes
# the result to step definitions as `driver`. Step definitions never construct a
# driver themselves.
module GreeterAcceptance
  module World
    def driver
      @driver ||= CompositionRoot.build_observed_driver
    end
  end
end

World(GreeterAcceptance::World)
