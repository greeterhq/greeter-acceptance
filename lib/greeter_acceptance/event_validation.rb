# frozen_string_literal: true

require_relative 'composition_root'

module GreeterAcceptance
  # Validates a channel-released event before anything acts on it. The event is
  # untrusted input: it names a channel, an environment, a version and a commit,
  # and nothing else gets through. In particular it can never carry a target
  # address; those come from the committed configuration.
  module EventValidation
    class Invalid < StandardError; end

    REQUIRED = %w[channel version sha environment].freeze
    ALLOWED = (REQUIRED + %w[artifact]).freeze
    ADDRESS_FIELDS = %w[url base_url target address].freeze

    VERSION = /\Av\d+\.\d+\.\d+\z/
    SHA = /\A[0-9a-f]{7,40}\z/
    ARTIFACT = /\A[a-z0-9_-]{1,32}\z/

    module_function

    # Returns the event reduced to its allowed fields. Raises Invalid otherwise.
    def validate(payload, environments:)
      raise Invalid, 'the event must be an object' unless payload.is_a?(Hash)

      refuse_target_address(payload)
      event = payload.slice(*ALLOWED)
      check_required(event)
      check_values(event, environments)
      event
    end

    def refuse_target_address(payload)
      field = ADDRESS_FIELDS.find { |name| payload.key?(name) }
      return if field.nil?

      raise Invalid, "the event carries a target address (#{field}); targets come only from the committed configuration"
    end

    def check_required(event)
      REQUIRED.each do |field|
        raise Invalid, "the event is missing #{field}" unless event.key?(field)
        raise Invalid, "#{field} must be a string" unless event[field].is_a?(String)
      end
    end

    def check_values(event, environments)
      unless CompositionRoot.channels.include?(event['channel'])
        raise Invalid, "unknown channel '#{event['channel']}'; expected one of: #{CompositionRoot.channels.join(', ')}"
      end
      unless environments.environments.include?(event['environment'])
        raise Invalid, "unknown environment '#{event['environment']}'"
      end

      check_formats(event)
    end

    def check_formats(event)
      raise Invalid, 'version must look like v1.2.3' unless VERSION.match?(event['version'])
      raise Invalid, 'sha must be 7 to 40 lowercase hex characters' unless SHA.match?(event['sha'])
      return unless event.key?('artifact') && !ARTIFACT.match?(event['artifact'].to_s)

      raise Invalid, 'artifact must be a short lowercase word'
    end
  end
end
