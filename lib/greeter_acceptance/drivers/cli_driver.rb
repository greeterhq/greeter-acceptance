# frozen_string_literal: true

require 'open3'

require_relative '../ports/greeter_driver'

module GreeterAcceptance
  module Drivers
    # Black-box adapter for the greeter CLI. Spawns `greeter <name>` and
    # translates its exit status into neutral outcomes. It never requires any
    # greeter-cli code; it only runs the process.
    #
    # Native idiom -> neutral outcome:
    #   exit 0 -> :greeted
    #   exit 2 -> :invalid_name
    class CliDriver
      include Ports::GreeterDriver

      EXIT_INVALID_NAME = 2

      def initialize(command: 'greeter', chdir: nil)
        @command = command
        @chdir = chdir
        @last_error = nil
        @last_native_error = nil
      end

      def channel
        :cli
      end

      def capabilities
        Set.new
      end

      # idempotency_key is accepted for port conformance but ignored: the CLI has
      # no idempotency concept.
      def greet(name, idempotency_key: nil) # rubocop:disable Lint/UnusedMethodArgument
        @last_error = nil
        @last_native_error = nil

        stdout, status = run(name)

        case status.exitstatus
        when 0
          Ports::GreetResult.new(
            message: stdout.chomp, guest_name: name, count: nil, outcome: :greeted
          )
        when EXIT_INVALID_NAME
          @last_native_error = status.exitstatus
          @last_error = :invalid_name
          Ports::GreetResult.new(
            message: nil, guest_name: name, count: nil, outcome: :invalid_name
          )
        else
          @last_native_error = status.exitstatus
          raise "greeter exited with unexpected status #{status.exitstatus}: #{stdout}"
        end
      end

      # The CLI cannot count; report the observation as not applicable.
      def count_for(_name)
        :not_applicable
      end

      attr_reader :last_error, :last_native_error

      private

      def run(name)
        options = {}
        options[:chdir] = @chdir if @chdir
        stdout, _stderr, status = Open3.capture3(@command, name.to_s, options)
        [stdout, status]
      end
    end
  end
end
