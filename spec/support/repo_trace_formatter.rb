# frozen_string_literal: true

require 'rspec/core'
require_relative 'repo_trace/document'

# RSpec formatter that writes the greeterhq.repo-trace.v1 file read by
# greeter-docs. Selected with `--format RepoTraceFormatter`; the path comes from
# REPO_TRACE_PATH (default tmp/repo-trace.json).
#
# It reads only the requirement/scenario metadata, the status and the location
# of each example tagged with both. It never reads descriptions or failure
# messages, which can contain guest names. A malformed value raises, and then
# nothing is written. It never touches tmp/traceability.json.
class RepoTraceFormatter
  RSpec::Core::Formatters.register self, :example_passed, :example_failed, :example_pending, :close

  DEFAULT_PATH = 'tmp/repo-trace.json'
  # "./spec/some_spec.rb:12:in `block ...'" -> "./spec/some_spec.rb:12"
  FILE_AND_LINE = /\A(.+?:\d+)/

  def initialize(output, env: ENV, clock: -> { Time.now }, root: Dir.pwd)
    @output = output
    @env = env
    @clock = clock
    @root = root
    @results = []
    @invalid = false
  end

  def example_passed(notification)
    record(notification.example, 'passed')
  end

  def example_failed(notification)
    record(notification.example, 'failed')
  end

  # RSpec reports both `skip` and `pending` here; only skip sets metadata[:skip].
  def example_pending(notification)
    example = notification.example
    record(example, example.metadata[:skip] ? 'skipped' : 'pending')
  end

  def close(_notification)
    return if @invalid

    RepoTrace::Document.write(path: @env.fetch('REPO_TRACE_PATH', DEFAULT_PATH), results: @results,
                              env: @env, clock: @clock, root: @root)
  end

  private

  def record(example, status)
    metadata = example.metadata
    return unless metadata[:requirement] && metadata[:scenario]

    @results << RepoTrace::Document.result(
      requirement: metadata[:requirement], scenario: metadata[:scenario], status: status,
      source: 'rspec', location: RepoTrace::Document.relative(location_of(example), @root)
    )
  rescue RepoTrace::Document::Invalid
    @invalid = true
    raise
  end

  # An example that comes from shared examples is located at the line that
  # included them (the outermost inclusion), so two inclusions of one shared
  # group, such as the driver contract in the cli and http specs, stay apart.
  def location_of(example)
    frame = example.metadata[:shared_group_inclusion_backtrace]&.last
    match = frame && FILE_AND_LINE.match(frame.inclusion_location.to_s)
    match ? match[1] : example.location
  end
end
