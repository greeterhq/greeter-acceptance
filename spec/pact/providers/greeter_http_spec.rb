# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'pact/rspec'

# add-pact-consumer: HttpDriver is the Pact consumer "greeter-acceptance" of the
# provider "greeter-http". The real driver, built by the composition root, sends
# every request to the Pact mock server, so the pact records exactly what the
# driver sends and reads. There is no missing-Idempotency-Key (400) interaction:
# the driver always sends a key, and a consumer contract describes only requests
# the consumer makes (design.md).
#
# Run with: bundle exec rspec -t pact spec/pact/providers
module GreeterHttpPact
  PACT_FILE = File.join('pacts', 'greeter-acceptance-greeter-http.json')
  REPLAY_KEY = '0b0e3a52-6f1c-4b8e-9d2a-2f3c1e4d5a6b'
  VERSION_PATTERN = /^\d+\.\d+\.\d+$/
  STATES = ['no greetings for ada', "ada has been greeted with key #{REPLAY_KEY}", 'any state'].freeze

  module_function

  def driver(mock_server)
    GreeterAcceptance::CompositionRoot.build_driver(
      env: { 'GREETER_CHANNEL' => 'http', 'GREETER_BASE_URL' => mock_server.url }
    )
  end

  def pact
    JSON.parse(File.read(PACT_FILE))
  end

  # A header value, looked up without regard to case. A V4 pact may write a
  # value as a string or as a one-element list.
  def header(headers, name)
    pair = (headers || {}).find { |key, _value| key.casecmp?(name) }
    pair && Array(pair.last).first
  end

  # A V4 body is wrapped as { "content", "contentType", "encoded" }.
  def body(part)
    body = part['body']
    body.is_a?(Hash) && body.key?('contentType') ? body['content'] : body
  end

  # The matcher entries for one path of one matching-rule category
  # ("body", "header"), looked up without regard to case.
  def matchers(part, category, path)
    rules = part.dig('matchingRules', category) || {}
    key = rules.keys.find { |candidate| candidate.casecmp?(path) }
    key ? Array(rules.dig(key, 'matchers')) : []
  end

  def match_types(part, category, path)
    matchers(part, category, path).map { |matcher| matcher['match'] }
  end
end

RSpec.describe 'greeter-http consumer contract', order: :defined do
  has_http_pact_between 'greeter-acceptance', 'greeter-http'

  # A local re-run must not merge stale interactions into the file CI publishes.
  # Once per run, before any interaction writes to the file: the interactions
  # merge into it in turn, and the last group reads the result.
  before(:context) { FileUtils.rm_f(GreeterHttpPact::PACT_FILE) } # rubocop:disable RSpec/BeforeAfterAll

  let(:request_headers) do
    { 'Content-Type' => 'application/json', 'X-Greeter-Synthetic' => 'true', 'Idempotency-Key' => match_uuid }
  end
  let(:version_headers) do
    {
      'X-Greeter-Version' => match_regex(GreeterHttpPact::VERSION_PATTERN, '1.0.0'),
      'X-Greeter-Core-Version' => match_regex(GreeterHttpPact::VERSION_PATTERN, '1.0.0')
    }
  end
  let(:greeted_body) do
    {
      'guest_name' => match_type_of('ada'),
      'greeting' => match_type_of('Hello, ada!'),
      'count' => match_any_integer(1),
      'greeted_at' => match_iso8601('2026-01-01T12:00:00Z')
    }
  end

  it 'answers a new greeting for ada with 201 and the success body',
     :aggregate_failures,
     requirement: 'the-contract-records-a-new-greeting',
     scenario: 'a-new-greeting-is-answered-201' do
    new_interaction.given('no greetings for ada').upon_receiving('a new greeting for ada')
                   .with_request(method: :post, path: '/greetings', headers: request_headers, body: { name: 'ada' })
                   .will_respond_with(status: 201, headers: version_headers, body: greeted_body)
                   .execute do |mock_server|
      driver = GreeterHttpPact.driver(mock_server)
      result = driver.greet('ada')

      expect([result.outcome, result.count, driver.last_native_error]).to eq([:greeted, 1, 201])
    end
  end

  it 'answers a replay with the known key with 200 and the same body shape',
     :aggregate_failures,
     requirement: 'the-contract-records-an-idempotent-replay',
     scenario: 'a-replay-with-a-known-key-is-answered-200' do
    headers = request_headers.merge('Idempotency-Key' => GreeterHttpPact::REPLAY_KEY)
    new_interaction.given(GreeterHttpPact::STATES[1]).upon_receiving('a replay of the greeting for ada')
                   .with_request(method: :post, path: '/greetings', headers: headers, body: { name: 'ada' })
                   .will_respond_with(status: 200, headers: version_headers, body: greeted_body)
                   .execute do |mock_server|
      driver = GreeterHttpPact.driver(mock_server)
      result = driver.greet('ada', idempotency_key: GreeterHttpPact::REPLAY_KEY)

      expect([result.outcome, result.count, driver.last_native_error]).to eq([:greeted, 1, 200])
    end
  end

  it 'answers an empty name with 422 invalid_name',
     :aggregate_failures,
     requirement: 'the-contract-records-an-invalid-name',
     scenario: 'an-empty-name-is-answered-422-invalid-name' do
    new_interaction.given('any state').upon_receiving('a greeting for an empty name')
                   .with_request(method: :post, path: '/greetings', headers: request_headers, body: { name: '' })
                   .will_respond_with(status: 422, body: { 'error' => 'invalid_name',
                                                           'message' => match_any_string('Invalid name.') })
                   .execute do |mock_server|
      driver = GreeterHttpPact.driver(mock_server)
      result = driver.greet('')

      expect([result.outcome, driver.last_error, driver.last_native_error]).to eq([:invalid_name, :invalid_name, 422])
    end
  end

  # These read the file the interactions above wrote, so they run last.
  describe 'the written pact' do
    let(:pact) { GreeterHttpPact.pact }
    let(:interactions) { pact.fetch('interactions') }
    let(:successes) { interactions.select { |i| [200, 201].include?(i.dig('response', 'status')) } }

    it 'names consumer greeter-acceptance and provider greeter-http and holds only this run',
       :aggregate_failures,
       requirement: 'the-http-driver-is-the-pact-consumer-of-greeter-http',
       scenario: 'a-pact-run-writes-the-greeter-acceptance-to-greeter-http-pact' do
      states = interactions.flat_map { |i| Array(i['providerStates']).map { |state| state['name'] } }

      expect(pact.dig('consumer', 'name')).to eq('greeter-acceptance')
      expect(pact.dig('provider', 'name')).to eq('greeter-http')
      expect(states).to match_array(GreeterHttpPact::STATES)
    end

    it 'holds exactly three interactions, each request with the synthetic header and a key',
       :aggregate_failures,
       requirement: 'the-contract-holds-only-requests-the-consumer-makes',
       scenario: 'three-interactions-each-with-the-synthetic-header-and-a-key' do
      headers = interactions.map { |i| i.dig('request', 'headers') }

      expect(interactions.size).to eq(3)
      expect(headers.map { |h| GreeterHttpPact.header(h, 'X-Greeter-Synthetic') }).to all(eq('true'))
      expect(headers.map { |h| GreeterHttpPact.header(h, 'Idempotency-Key') }).to all(match(/\A\h{8}-\h{4}-/))
    end

    it 'expects count as an integer and matches every provider-chosen value by type or pattern',
       :aggregate_failures,
       requirement: 'provider-chosen-values-are-matched-by-type-or-pattern',
       scenario: 'count-is-expected-as-an-integer' do
      expect(successes.size).to eq(2)
      successes.map { |i| i['response'] }.each do |response|
        expect(GreeterHttpPact.body(response)).to include('count')
        expect(GreeterHttpPact.match_types(response, 'body', '$.count')).to eq(['integer'])
        expect(%w[$.guest_name $.greeting].map { |path| GreeterHttpPact.match_types(response, 'body', path) })
          .to eq([['type'], ['type']])
        expect(GreeterHttpPact.match_types(response, 'body', '$.greeted_at')).to eq(['regex'])
        %w[X-Greeter-Version X-Greeter-Core-Version].each do |name|
          expect(GreeterHttpPact.matchers(response, 'header', name).map { |m| m['regex'] })
            .to contain_exactly(include('^\d+\.\d+\.\d+$'))
        end
      end
    end
  end
end
