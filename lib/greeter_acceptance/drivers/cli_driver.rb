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
    #   exit 0                       -> :greeted
    #   exit 2                       -> :invalid_name
    #   anything else, or the command
    #   could not be run             -> :infrastructure_error (never raised)
    class CliDriver
      include Ports::GreeterDriver

      EXIT_INVALID_NAME = 2

      # `greeter --version` prints: greeter-cli <version> (greeter-core <version>)
      VERSION_LINE = /\Agreeter-cli\s+(\S+)\s+\(greeter-core\s+(\S+)\)\s*\z/

      def initialize(command: 'greeter', chdir: nil)
        @command = command
        @chdir = chdir
        @last_error = nil
        @last_native_error = nil
        @build_info = nil
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

        stdout, status = run(name.to_s)
        outcome_for(name, stdout, status.exitstatus)
      rescue SystemCallError => e
        infrastructure_error(name, e.class.name)
      end

      # The CLI cannot count; report the observation as not applicable.
      def count_for(_name)
        :not_applicable
      end

      # Reads the versions from `<command> --version`. A successful read is
      # cached; an unparseable or failed one returns nil and is retried next time.
      def build_info
        @build_info ||= read_build_info
      end

      attr_reader :last_error, :last_native_error

      private

      def outcome_for(name, stdout, exit_status)
        case exit_status
        when 0 then greeted(name, stdout)
        when EXIT_INVALID_NAME then invalid_name(name, exit_status)
        else infrastructure_error(name, exit_status)
        end
      end

      def greeted(name, stdout)
        Ports::GreetResult.new(message: stdout.chomp, guest_name: name, count: nil, outcome: :greeted)
      end

      def invalid_name(name, exit_status)
        @last_native_error = exit_status
        @last_error = :invalid_name
        Ports::GreetResult.new(message: nil, guest_name: name, count: nil, outcome: :invalid_name)
      end

      def infrastructure_error(name, native)
        @last_native_error = native
        @last_error = :infrastructure_error
        Ports::GreetResult.new(message: nil, guest_name: name, count: nil, outcome: :infrastructure_error)
      end

      def read_build_info
        stdout, status = run('--version')
        match = VERSION_LINE.match(stdout.to_s.strip)
        return nil unless status.success? && match

        Ports::BuildInfo.new(channel_version: match[1], core_version: match[2])
      rescue SystemCallError
        nil
      end

      def run(*)
        options = {}
        options[:chdir] = @chdir if @chdir
        stdout, _stderr, status = Open3.capture3(@command, *, **options)
        [stdout, status]
      end
    end
  end
end
