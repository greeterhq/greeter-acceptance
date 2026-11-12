# frozen_string_literal: true

require_relative 'drivers/cli_driver'
require_relative 'drivers/http_driver'
require_relative 'observed'

module GreeterAcceptance
  # The ONLY place a driver is constructed. It picks the channel adapter from
  # GREETER_CHANNEL (cli|http). features/support/env.rb and bin/* only call it,
  # and nothing else knows which concrete driver a channel uses.
  #
  # This supersedes the rule from add-neutral-acceptance-suite that
  # features/support/env.rb is the only composition root: that file cannot be
  # loaded outside Cucumber, so bin/ scripts could not build a driver.
  module CompositionRoot
    class ConfigurationError < StandardError; end

    CHANNELS = %w[cli http].freeze

    module_function

    # Every channel the suite knows how to drive.
    def channels
      CHANNELS
    end

    # A raw driver, for bin/* scripts and specs.
    def build_driver(env: ENV)
      channel = env['GREETER_CHANNEL'].to_s
      raise ConfigurationError, "GREETER_CHANNEL is not set; expected one of: #{channels.join(', ')}" if channel.empty?

      case channel
      when 'cli' then cli_driver(env)
      when 'http' then Drivers::HttpDriver.new(base_url: base_url(env))
      else
        raise ConfigurationError,
              "GREETER_CHANNEL=#{channel} is not a known channel; expected one of: #{channels.join(', ')}"
      end
    end

    # A driver wrapped in the observing decorator, for the Cucumber World.
    def build_observed_driver(env: ENV)
      Observed.new(build_driver(env: env))
    end

    def cli_driver(env)
      Drivers::CliDriver.new(command: env.fetch('GREETER_CLI_CMD', 'greeter'), chdir: env['GREETER_CLI_DIR'])
    end

    def base_url(env)
      env.fetch('GREETER_BASE_URL') do
        raise ConfigurationError, 'GREETER_BASE_URL is required when GREETER_CHANNEL=http'
      end
    end
  end
end
