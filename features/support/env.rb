# frozen_string_literal: true

require_relative '../../lib/greeter_acceptance/drivers/cli_driver'
require_relative '../../lib/greeter_acceptance/drivers/http_driver'

# The ONLY composition root. It picks the channel adapter from GREETER_CHANNEL
# and exposes it to step definitions as `driver`. Step definitions never
# construct a driver themselves.
module GreeterAcceptance
  module World
    def driver
      @driver ||= GreeterAcceptance.build_driver
    end
  end

  module_function

  def build_driver
    case ENV.fetch('GREETER_CHANNEL', nil)
    when 'cli'
      Drivers::CliDriver.new(
        command: ENV.fetch('GREETER_CLI_CMD', 'greeter'),
        chdir: ENV.fetch('GREETER_CLI_DIR', nil)
      )
    when 'http'
      Drivers::HttpDriver.new(base_url: fetch_base_url)
    when nil, ''
      raise 'GREETER_CHANNEL is not set; expected one of: cli, http'
    else
      raise "GREETER_CHANNEL=#{ENV.fetch('GREETER_CHANNEL')} is not a known channel; expected one of: cli, http"
    end
  end

  def fetch_base_url
    ENV.fetch('GREETER_BASE_URL') do
      raise 'GREETER_BASE_URL is required when GREETER_CHANNEL=http'
    end
  end
end

World(GreeterAcceptance::World)
