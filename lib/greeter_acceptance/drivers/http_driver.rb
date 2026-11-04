# frozen_string_literal: true

require 'json'
require 'net/http'
require 'securerandom'
require 'uri'

require_relative '../ports/greeter_driver'

module GreeterAcceptance
  module Drivers
    # Black-box adapter for the greeter HTTP service. POSTs to /greetings over
    # Net::HTTP and translates HTTP status into neutral outcomes. It never
    # requires any greeter-http code; it only talks to a URL.
    #
    # Native idiom -> neutral outcome:
    #   201, 200 -> :greeted
    #   422      -> :invalid_name
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
    class HttpDriver
      include Ports::GreeterDriver

      SYNTHETIC_HEADER = 'X-Greeter-Synthetic'

      def initialize(base_url:, synthetic: true)
        @base_url = base_url
        @synthetic = synthetic
        @last_error = nil
        @last_native_error = nil
        @counts = {}
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

        case response.code.to_i
        when 200, 201
          body = parse_body(response)
          count = extract_count(body)
          @counts[name] = count unless count.nil?
          Ports::GreetResult.new(
            message: body_message(body), guest_name: name, count: count, outcome: :greeted
          )
        when 422
          @last_error = :invalid_name
          Ports::GreetResult.new(
            message: nil, guest_name: name, count: nil, outcome: :invalid_name
          )
        else
          raise "greeter-http returned unexpected status #{response.code}: #{response.body}"
        end
      end

      def count_for(name)
        @counts[name]
      end

      attr_reader :last_error, :last_native_error

      private

      def post_greeting(name, idempotency_key)
        uri = URI.join(@base_url, '/greetings')
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request[SYNTHETIC_HEADER] = 'true' if @synthetic
        request['Idempotency-Key'] = idempotency_key || SecureRandom.uuid
        request.body = JSON.generate(name: name)

        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
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
