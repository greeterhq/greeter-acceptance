# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

require_relative 'deployed'
require_relative 'ledger'
require_relative 'ledger_renderer'
require_relative 'publisher/files'
require_relative 'publisher/git'
require_relative 'publisher/validation'

module GreeterAcceptance
  # Publishes one channel's result to a ledger branch, and keeps the branch
  # convergent when several channels publish at once.
  #
  # The branch holds source records (channels/<channel>.json and deployed.json)
  # and two generated views (ledger.json and LEDGER.md). A publication writes only
  # its own channel's result and its own entry in the deployed record, then
  # regenerates the views from every record on the branch.
  #
  # Two publishers always touch the same generated files, so a rebase would
  # conflict on exactly those. A publication therefore never rebases: when its
  # push is rejected it starts again from the branch as it now is (fetch, apply
  # its own change, regenerate, push), and it never forces. The result it is given
  # is untrusted data (see Validation), and nothing in it is executed.
  #
  # Standard library only: the stage that runs this holds write access and installs
  # no gems.
  class Publisher
    class Refused < StandardError; end
    class PushRejected < StandardError; end

    # One publication: the channel, its cleaned result, its cleaned deployment
    # entry, and whether the ordering checks are skipped.
    Change = Struct.new(:channel, :record, :entry, :force, keyword_init: true)

    include Files
    include Validation

    DEFAULT_AUTHOR = {
      name: 'github-actions[bot]', email: '41898282+github-actions[bot]@users.noreply.github.com'
    }.freeze

    # How many pushes were tried by the last #publish.
    attr_reader :attempts

    # before_push, when given, is called with the attempt number after the commit
    # and before each push. It is a seam for tests to make a rival publish first.
    def initialize(remote:, branch:, environment:, suite_version:, channels:, requirements:,
                   max_attempts: 5, max_result_bytes: 1_048_576, before_push: nil, author: DEFAULT_AUTHOR)
      @remote = remote
      @branch = branch
      @environment = environment
      @suite_version = suite_version
      @channels = channels
      @requirements = requirements
      @max_attempts = max_attempts
      @max_result_bytes = max_result_bytes
      @before_push = before_push
      @author = author
      @attempts = 0
    end

    # Returns :committed, or :unchanged when the branch already says the same.
    # Raises Refused for anything it will not publish, PushRejected when the branch
    # keeps moving under it. force skips the ordering checks and is recorded in the
    # channel's result together with the actor.
    #
    # A nil result records only the deployment: a run that produced no result at
    # all (its artifact could not be fetched, say) must still say that the new
    # version is deployed. The channel's earlier result is left as it was, so its
    # column in the ledger goes stale rather than disappearing.
    def publish(channel:, result:, deployment:, force: false, actor: nil)
      raise Refused, 'a forced publication must name the actor' if force && actor.to_s.empty?

      record = result.nil? ? nil : clean_result(result, channel)
      record['run']['forced'] = actor if force && record
      change = Change.new(channel: channel, record: record, entry: clean_deployment(deployment), force: force)
      @attempts = 0
      Dir.mktmpdir('ledger-publish') { |dir| push_until_accepted(dir, change) }
    end

    private

    def push_until_accepted(dir, change)
      git = Git.new(dir, @author)
      last_output = nil
      while @attempts < @max_attempts
        @attempts += 1
        fresh_checkout(dir, git)
        return :unchanged if apply_change(dir, git, change) == :unchanged

        @before_push&.call(@attempts)
        last_output, pushed = git.attempt('push', '-q', 'origin', "HEAD:refs/heads/#{@branch}")
        return :committed if pushed
      end
      raise PushRejected, "could not publish to #{@branch} after #{@attempts} attempts: #{last_output}"
    end

    # Start from the branch as the remote has it now, with nothing left over from
    # an earlier attempt.
    def fresh_checkout(dir, git)
      FileUtils.rm_rf(Dir.children(dir).map { |name| File.join(dir, name) })
      git.run('init', '-q', '--template=')
      git.run('remote', 'add', 'origin', @remote)
      if remote_branch?(git)
        git.run('fetch', '-q', 'origin', @branch)
        git.run('checkout', '-q', '-B', @branch, 'FETCH_HEAD')
      else
        git.run('symbolic-ref', 'HEAD', "refs/heads/#{@branch}")
      end
    end

    def remote_branch?(git)
      _output, found = git.attempt('ls-remote', '--exit-code', '--heads', 'origin', @branch)
      found
    end

    # Writes this publication's change and commits it: :ready, or :unchanged when
    # the branch already says the same.
    def apply_change(dir, git, change)
      deployed = read_json(dir, 'deployed.json') || Deployed.empty(environment: @environment)
      check_not_older(deployed, read_json(dir, 'ledger.json'), change) unless change.force

      write_json(dir, "channels/#{change.channel}.json", change.record) if change.record
      write_json(dir, 'deployed.json', updated_deployed(deployed, change.channel, change.entry))
      write_views(dir)
      commit(git, change)
    end

    # Never go backwards: an older channel version must not replace a newer one,
    # nor an older suite version lower the ledger's.
    def check_not_older(deployed, ledger, change)
      version = change.entry['version']
      recorded = deployed.dig('channels', change.channel, 'version')
      if recorded && semantic(version) < semantic(recorded)
        raise Refused, "version #{version} is older than #{recorded}, which is already recorded for #{change.channel}"
      end

      suite = ledger&.dig('suite', 'version')
      return unless suite && semantic(@suite_version) < semantic(suite)

      raise Refused, "suite version #{@suite_version} is older than #{suite}, which the ledger already records"
    end

    def commit(git, change)
      git.run('add', '-A')
      return :unchanged if git.run('status', '--porcelain').empty?

      message = "ledger(#{@environment}): #{change.channel} #{change.entry['version']} (suite #{@suite_version})"
      message += ' [forced]' if change.force
      git.run('commit', '-q', '-m', message)
      :ready
    end
  end
end
