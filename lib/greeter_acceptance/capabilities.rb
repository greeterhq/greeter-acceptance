# frozen_string_literal: true

module GreeterAcceptance
  # The single source of truth for capability names the suite understands.
  # A @capability-<name> tag whose name is not here is a mistake, caught at
  # startup by the tag-validation check rather than silently failing a channel.
  module Capabilities
    KNOWN = Set[:counting, :idempotency].freeze

    TAG_PATTERN = /\A@capability-(.+)\z/

    module_function

    # Extracts the capability symbols required by a collection of tag names.
    def required_from_tags(tag_names)
      tag_names.filter_map do |tag|
        match = TAG_PATTERN.match(tag)
        match && match[1].to_sym
      end
    end

    def known?(capability)
      KNOWN.include?(capability)
    end
  end
end
