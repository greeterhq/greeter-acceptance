# frozen_string_literal: true

require 'open3'

module GreeterAcceptance
  class Publisher
    # A thin wrapper over the git command line, in one working directory. Standard
    # library only: the publishing stage has write access and installs no gems.
    #
    # Hooks are switched off on every call. The working directory is a throwaway
    # repository that only this class writes to, so a hook can only ever come from
    # the surrounding environment (a global template directory, say), and running
    # code the environment happens to install is exactly what this stage must not
    # do. Signing is off for the same reason: there is no key to prompt for.
    class Git
      class Failure < StandardError; end

      SETTINGS = ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false'].freeze

      def initialize(dir, author)
        @dir = dir
        @env = {
          'GIT_AUTHOR_NAME' => author.fetch(:name), 'GIT_AUTHOR_EMAIL' => author.fetch(:email),
          'GIT_COMMITTER_NAME' => author.fetch(:name), 'GIT_COMMITTER_EMAIL' => author.fetch(:email),
          'GIT_TERMINAL_PROMPT' => '0'
        }
      end

      # Runs git and returns its output, raising Failure if it fails.
      def run(*args)
        output, ok = attempt(*args)
        raise Failure, "git #{args.join(' ')} failed: #{output}" unless ok

        output
      end

      # Runs git and returns [output, succeeded].
      def attempt(*)
        output, status = Open3.capture2e(@env, 'git', *SETTINGS, *, chdir: @dir)
        [output, status.success?]
      end
    end
  end
end
