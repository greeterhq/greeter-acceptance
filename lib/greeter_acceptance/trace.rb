# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module GreeterAcceptance
  # Collects one row per scenario for the channel under test and writes
  # tmp/traceability.json in the greeterhq.traceability.v1 schema. One instance
  # per run; the composition root owns it and the hooks feed it.
  class Trace
    SCHEMA = 'greeterhq.traceability.v1'

    REQUIREMENT_TAG = /\A@requirement-(.+)\z/
    SCENARIO_TAG = /\A@scenario-(.+)\z/

    def initialize(channel:, output_path: 'tmp/traceability.json', clock: Time)
      @channel = channel
      @output_path = output_path
      @clock = clock
      @rows = []
    end

    # status: :passed | :failed | :not_applicable
    # missing_capabilities: array of symbols, only meaningful for :not_applicable
    def record(tag_names:, status:, missing_capabilities: [])
      @rows << {
        requirement: slug_from(tag_names, REQUIREMENT_TAG),
        scenario: slug_from(tag_names, SCENARIO_TAG),
        status: status.to_s,
        missing_capabilities: missing_capabilities.map(&:to_s)
      }.tap { |row| row.delete(:missing_capabilities) if status != :not_applicable }
    end

    # Writes the canonical tmp/traceability.json for this run, plus a
    # channel-tagged copy (tmp/traceability-<channel>.json) so both channels'
    # files coexist for the merge step without overwriting each other.
    def write
      payload = "#{JSON.pretty_generate(document)}\n"

      FileUtils.mkdir_p(File.dirname(@output_path))
      File.write(@output_path, payload)
      File.write(channel_output_path, payload)
      @output_path
    end

    def channel_output_path
      dir = File.dirname(@output_path)
      ext = File.extname(@output_path)
      base = File.basename(@output_path, ext)
      File.join(dir, "#{base}-#{@channel}#{ext}")
    end

    def document
      {
        'schema' => SCHEMA,
        'run' => {
          'channel' => @channel.to_s,
          'at' => @clock.now.utc.iso8601,
          'acceptance_ref' => ENV.fetch('ACCEPTANCE_REF', nil)
        },
        'results' => @rows.map { |row| stringify(row) }
      }
    end

    private

    def slug_from(tag_names, pattern)
      tag_names.each do |tag|
        match = pattern.match(tag)
        return match[1] if match
      end
      nil
    end

    def stringify(row)
      row.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = value
      end
    end
  end
end
