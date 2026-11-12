# frozen_string_literal: true

require_relative 'event_validation'

module GreeterAcceptance
  # Decides what a record run has to test. A channel-released event yields that
  # one channel. A new suite version, or a manual run asking to re-run
  # everything, yields every channel named in each environment's deployed record
  # at the version recorded there. Every entry is validated the same way, and
  # carries the ledger branch of its environment from the committed configuration.
  class Resolver
    VERSION_TAG = /\Av\d+\.\d+\.\d+\z/

    # The highest released suite version, compared by number. Pre-releases and
    # non-version tags are ignored, and so is the default branch: only a
    # published version is ever run.
    def self.latest_suite_tag(tags)
      tags.grep(VERSION_TAG).max_by { |tag| Gem::Version.new(tag.delete_prefix('v')) }
    end

    def initialize(environments:)
      @environments = environments
    end

    # trigger: :channel_released | :suite_tag | :manual
    def matrix(trigger:, payload: {}, deployed: {}, rerun_all: false)
      case trigger
      when :channel_released then from_event(payload)
      when :suite_tag then from_deployed(deployed)
      when :manual then rerun_all ? from_deployed(deployed) : from_event(payload)
      else raise ArgumentError, "unknown trigger #{trigger.inspect}"
      end
    end

    private

    def from_event(payload)
      [entry_for(EventValidation.validate(payload, environments: @environments))]
    end

    def from_deployed(deployed)
      deployed.sort.flat_map do |environment, document|
        document.fetch('channels', {}).sort.map do |channel, recorded|
          event = recorded.slice('version', 'sha', 'artifact').merge('channel' => channel, 'environment' => environment)
          entry_for(EventValidation.validate(event, environments: @environments))
        end
      end
    end

    def entry_for(event)
      {
        'channel' => event['channel'], 'version' => event['version'], 'sha' => event['sha'],
        'artifact' => event['artifact'], 'environment' => event['environment'],
        'ledger_branch' => @environments.ledger_branch(event['environment'])
      }
    end
  end
end
