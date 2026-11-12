# frozen_string_literal: true

module GreeterAcceptance
  # Wraps a driver, implements the same port, and remembers what the wrapped
  # driver reports so hooks can read it after a scenario. Steps only ever see the
  # port; they do not know this decorator exists.
  #
  # It exists because a driver's #last_error is cleared by its next greet, so an
  # infrastructure error in the middle of a scenario would otherwise be lost, and
  # because each scenario gets a driver of its own, so what one learns about the
  # channel's version would be lost with it.
  class Observed
    def initialize(driver)
      @driver = driver
      @infrastructure_error = false
      @build_infos = []
    end

    # Read-only port methods are forwarded unchanged.
    def channel
      @driver.channel
    end

    def capabilities
      @driver.capabilities
    end

    def supports?(capability)
      @driver.supports?(capability)
    end

    def count_for(name)
      @driver.count_for(name)
    end

    def last_error
      @driver.last_error
    end

    def last_native_error
      @driver.last_native_error
    end

    def native_idiom_for?(error)
      @driver.native_idiom_for?(error)
    end

    def greet(name, idempotency_key: nil)
      result = @driver.greet(name, idempotency_key: idempotency_key)
      @infrastructure_error = true if result.outcome == :infrastructure_error
      result
    end

    def build_info
      info = @driver.build_info
      @build_infos << info unless info.nil? || @build_infos.include?(info)
      info
    end

    # True once any greeting in this scenario hit an infrastructure error, even if
    # a later one succeeded.
    def infrastructure_error?
      @infrastructure_error
    end

    # The distinct, observable build information seen so far.
    def build_infos
      @build_infos.dup
    end
  end
end
