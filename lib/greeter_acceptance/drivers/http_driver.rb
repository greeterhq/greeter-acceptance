# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'securerandom'
require 'timeout'
require 'uri'

require_relative '../ports/greeter_driver'

module GreeterAcceptance
  module Drivers
    # Black-box adapter for the greeter HTTP service. POSTs to /greetings over
    # Net::HTTP and translates HTTP status into neutral outcomes. It never
    # requires any greeter-http code; it only talks to a URL.
    #
    # Native idiom -> neutral outcome:
    #   201, 200                       -> :greeted
    #   422                            -> :invalid_name
    #   anything else, or the service
    #   could not be reached           -> :infrastructure_error (never raised)
    #
    # The service REQUIRES an Idempotency-Key on every request (a missing key is
    # 400). When the caller supplies no key (the ordinary, non-idempotency
    # scenarios), the driver generates a fresh unique one so each call is a
    # distinct greeting; a caller-supplied key is passed through unchanged so
    # replays with the same key are idempotent.
    #
    # Observed success body (design open question resolved against the live
    # service): { "guest_name", "greeting", "count", "greeted_at" }. The count
    # is the top-level "count"; the human message is "greeting".
    #
    # Build information: the service is expected to report its versions in the
    # two headers below on every response. Until greeter-http does, build_info
    # is nil. The header names are the only thing to change if it chooses others.
    class HttpDriver
      include Ports::GreeterDriver

      SYNTHETIC_HEADER = 'X-Greeter-Synthetic'
      VERSION_HEADER = 'X-Greeter-Version'
      CORE_VERSION_HEADER = 'X-Greeter-Core-Version'

      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 30

      NETWORK_ERRORS = [
        SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError,
        Net::ProtocolError, Net::HTTPBadResponse
      ].freeze

      def initialize(base_url:, synthetic: true)
        @base_url = base_url
        @synthetic = synthetic
        @last_error = nil
        @last_native_error = nil
        @counts = {}
        @build_info = nil
        @requests = 0
      end

      def channel
        :http
      end

      def capabilities
        Set[:counting, :idempotency]
      end

      def greet(name, idempotency_key: nil)
        @last_error = nil
        @last_native_error = nil

        response = post_greeting(name, idempotency_key)
        @last_native_error = response.code.to_i
        remember_build_info(response)
        outcome_for(name, response)
      rescue *NETWORK_ERRORS => e
        infrastructure_error(name, e.class.name)
      end

      def count_for(name)
        @counts[name]
      end

      # The versions the service has reported. If this driver has not contacted
      # the service yet, probe with an invalid name: it is rejected (422) so
      # nothing is greeted and no count changes, and only the response headers are
      # read. Once a response has been seen without version headers, a probe would
      # not see any either, so it is not repeated.
      def build_info
        probe_build_info if @build_info.nil? && @requests.zero?
        @build_info
      end

      attr_reader :last_error, :last_native_error

      private

      def outcome_for(name, response)
        case response.code.to_i
        when 200, 201 then greeted(name, parse_body(response))
        when 422 then invalid_name(name)
        else infrastructure_error(name, response.code.to_i)
        end
      end

      def greeted(name, body)
        count = extract_count(body)
        @counts[name] = count unless count.nil?
        Ports::GreetResult.new(message: body_message(body), guest_name: name, count: count, outcome: :greeted)
      end

      def invalid_name(name)
        @last_error = :invalid_name
        Ports::GreetResult.new(message: nil, guest_name: name, count: nil, outcome: :invalid_name)
      end

      def infrastructure_error(name, native)
        @last_native_error = native
        @last_error = :infrastructure_error
        Ports::GreetResult.new(message: nil, guest_name: name, count: nil, outcome: :infrastructure_error)
      end

      def probe_build_info
        remember_build_info(post_greeting('', nil))
      rescue *NETWORK_ERRORS
        nil
      end

      def remember_build_info(response)
        version = response[VERSION_HEADER]
        return if version.nil? || version.empty?

        @build_info = Ports::BuildInfo.new(channel_version: version, core_version: response[CORE_VERSION_HEADER])
      end

      def post_greeting(name, idempotency_key)
        @requests += 1
        uri = URI.join(@base_url, '/greetings')
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request[SYNTHETIC_HEADER] = 'true' if @synthetic
        request['Idempotency-Key'] = idempotency_key || SecureRandom.uuid
        request.body = JSON.generate(name: name)

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                                                open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end
      end

      def parse_body(response)
        return {} if response.body.nil? || response.body.empty?

        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end

      def extract_count(body)
        body['count'] if body.is_a?(Hash)
      end

      def body_message(body)
        body.is_a?(Hash) ? body['greeting'] : nil
      end
    end
  end
end
