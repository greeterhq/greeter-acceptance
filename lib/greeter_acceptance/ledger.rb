# frozen_string_literal: true

require 'json'
require 'fileutils'

module GreeterAcceptance
  # Derives the cross-channel ledger (tmp/ledger.json) by merging the per-channel
  # traceability.json files from each run into a requirement-by-channel matrix.
  # This is the published view of the capability frontier. Merging is a separate
  # step because a single Cucumber run only ever sees one channel.
  class Ledger
    SCHEMA = 'greeterhq.ledger.v1'

    def self.from_files(paths)
      new(paths.map { |path| JSON.parse(File.read(path)) })
    end

    def initialize(trace_documents)
      @traces = trace_documents
    end

    def channels
      @traces.map { |trace| trace.dig('run', 'channel') }
    end

    def document
      {
        'schema' => SCHEMA,
        'channels' => channels,
        'requirements' => requirements_matrix
      }
    end

    def write(output_path = 'tmp/ledger.json')
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, "#{JSON.pretty_generate(document)}\n")
      output_path
    end

    private

    def requirements_matrix
      matrix = Hash.new { |hash, key| hash[key] = {} }

      @traces.each do |trace|
        channel = trace.dig('run', 'channel')
        Array(trace['results']).each do |row|
          matrix[row['requirement']][channel] = row['status']
        end
      end

      matrix
    end
  end
end
