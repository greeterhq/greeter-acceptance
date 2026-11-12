# frozen_string_literal: true

# A hand-written GreeterDriver stand-in that returns scripted greet results.
# It implements the port by hand rather than inheriting from lib/, so specs that
# use it fail on the class under test and not on the stand-in.
class ScriptedDriver
  attr_reader :channel, :capabilities, :build_info, :last_error, :greets

  def initialize(results: [], build_info: nil, capabilities: Set[:counting], channel: :http)
    @results = results.dup
    @build_info = build_info
    @capabilities = capabilities
    @channel = channel
    @greets = []
    @last_error = nil
  end

  def supports?(capability)
    @capabilities.include?(capability)
  end

  def greet(name, idempotency_key: nil)
    @greets << [name, idempotency_key]
    result = @results.shift or raise 'ScriptedDriver has no more scripted results'
    @last_error = result.outcome == :greeted ? nil : result.outcome
    result
  end

  def count_for(_name)
    7
  end

  def last_native_error
    'native'
  end

  def native_idiom_for?(error)
    last_error == error
  end
end
