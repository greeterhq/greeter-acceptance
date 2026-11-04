# frozen_string_literal: true

module GreeterAcceptance
  module Ports
    # The neutral result of a greet attempt. `outcome` is :greeted for both a
    # first greeting and a repeat; `count` carries the new-vs-repeat distinction
    # on counting channels and is nil elsewhere. `count` is part of the specified
    # port surface, so the Struct#count override is intentional.
    GreetResult = Struct.new(:message, :guest_name, :count, :outcome, keyword_init: true) # rubocop:disable Lint/StructNewOverride

    # GreeterDriver is the only interface step definitions may call. Each channel
    # adapter includes this module and implements the channel-specific methods;
    # the module supplies behaviour that is identical across channels.
    #
    # Required of including adapters:
    #   channel           -> Symbol   (:cli, :http, ...)
    #   capabilities      -> Set[Symbol]
    #   greet(name, idempotency_key:) -> GreetResult
    #   count_for(name)   -> Integer, or :not_applicable when counting unsupported
    #   last_error        -> neutral Symbol (:invalid_name, ...) or nil
    #   last_native_error -> channel-native detail (debugging only)
    module GreeterDriver
      class NotImplementedInAdapter < StandardError
      end

      # A capability is supported exactly when the adapter declares it.
      def supports?(capability)
        capabilities.include?(capability)
      end

      # True when the last neutral error corresponds to the given neutral symbol.
      # Adapters that need channel-specific judgement may override this.
      def native_idiom_for?(error)
        last_error == error
      end

      def channel
        raise NotImplementedInAdapter, "#{self.class} must implement #channel"
      end

      def capabilities
        raise NotImplementedInAdapter, "#{self.class} must implement #capabilities"
      end

      # idempotency_key is kept in the signature to document the port surface.
      def greet(_name, idempotency_key: nil) # rubocop:disable Lint/UnusedMethodArgument
        raise NotImplementedInAdapter, "#{self.class} must implement #greet"
      end

      def count_for(_name)
        raise NotImplementedInAdapter, "#{self.class} must implement #count_for"
      end

      def last_error
        raise NotImplementedInAdapter, "#{self.class} must implement #last_error"
      end

      def last_native_error
        raise NotImplementedInAdapter, "#{self.class} must implement #last_native_error"
      end
    end
  end
end
