# frozen_string_literal: true

module GreeterAcceptance
  # The deployed record (greeterhq.deployed.v1): which version and commit of each
  # channel is deployed in one environment. It is updated whenever a channel is
  # released, whatever its tests then say, so it stays true even when a run fails
  # or errors. Documents are plain hashes; every method returns a new one.
  module Deployed
    SCHEMA = 'greeterhq.deployed.v1'

    module_function

    def empty(environment:)
      { 'schema' => SCHEMA, 'environment' => environment, 'channels' => {} }
    end

    # Replaces the entry of one channel and leaves every other entry untouched.
    # artifact and run_id are omitted from the entry when they are nil.
    def update(document, channel:, version:, sha:, run_id: nil, artifact: nil)
      entry = { 'version' => version, 'sha' => sha, 'artifact' => artifact, 'run_id' => run_id }.compact
      document.merge('channels' => document.fetch('channels').merge(channel => entry))
    end
  end
end
