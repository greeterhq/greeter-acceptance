# frozen_string_literal: true

require 'uri'
require 'yaml'

module GreeterAcceptance
  # Resolves which endpoint a run targets, from the committed configuration only
  # (config/environments.yml on the default branch). A target address is never
  # taken from an event, a workflow input or any other caller, and an http
  # target's host must match its environment's allowed pattern before any request
  # is made.
  class Environments
    class Refused < StandardError; end

    # base_url is set for a service channel, repo for an artifact channel.
    Target = Struct.new(:environment, :channel, :base_url, :repo, keyword_init: true)

    def self.load(path)
      new(YAML.safe_load_file(path))
    end

    def initialize(config)
      @environments = config.fetch('environments')
    end

    def environments
      @environments.keys
    end

    def channels_for(environment)
      environment_config(environment).fetch('channels', {}).keys
    end

    def ledger_branch(environment)
      environment_config(environment).fetch('ledger_branch')
    end

    def resolve(environment:, channel:, requested_address: nil)
      unless requested_address.nil?
        raise Refused, 'a target address was supplied; targets come only from the committed configuration'
      end

      entry = environment_config(environment).fetch('channels', {})[channel]
      raise Refused, "no target for channel '#{channel}' in environment '#{environment}'" if entry.nil?

      build_target(environment, channel, entry)
    end

    private

    def environment_config(environment)
      @environments.fetch(environment) { raise Refused, "unknown environment '#{environment}'" }
    end

    def build_target(environment, channel, entry)
      return Target.new(environment: environment, channel: channel, repo: entry['repo']) unless entry.key?('base_url')

      check_host(environment, channel, entry)
      Target.new(environment: environment, channel: channel, base_url: entry['base_url'])
    end

    def check_host(environment, channel, entry)
      host = host_of(entry['base_url'], environment, channel)
      return if Regexp.new(entry.fetch('host_pattern')).match?(host)

      raise Refused, "host '#{host}' of the #{channel} target in environment '#{environment}' " \
                     'does not match its allowed host pattern'
    end

    def host_of(base_url, environment, channel)
      host = URI.parse(base_url.to_s).host
      return host unless host.nil? || host.empty?

      raise Refused, "the #{channel} target in environment '#{environment}' has no host"
    rescue URI::InvalidURIError
      raise Refused, "the #{channel} target in environment '#{environment}' is not a valid address"
    end
  end
end
