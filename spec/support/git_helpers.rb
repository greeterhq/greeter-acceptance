# frozen_string_literal: true

require 'open3'
require 'tmpdir'

# Thin wrappers over the git command line, used to inspect a local bare
# repository that stands in for the remote holding a ledger branch.
module GitHelpers
  def run_git(*args, git_dir: nil)
    command = ['git']
    command << "--git-dir=#{git_dir}" if git_dir
    output, status = Open3.capture2e(*command, *args)
    raise "git #{args.join(' ')} failed: #{output}" unless status.success?

    output
  end

  def init_bare_remote
    dir = Dir.mktmpdir('ledger-remote')
    run_git('init', '--bare', dir)
    dir
  end

  def branch_file(remote, branch, path)
    run_git('show', "#{branch}:#{path}", git_dir: remote)
  end

  def branch_files(remote, branch)
    run_git('ls-tree', '-r', '--name-only', branch, git_dir: remote).split("\n")
  end

  def branch_head(remote, branch)
    run_git('rev-parse', branch, git_dir: remote).strip
  end

  def branch_exists?(remote, branch)
    _output, status = Open3.capture2e('git', "--git-dir=#{remote}", 'rev-parse', '--verify', '--quiet', branch)
    status.success?
  end

  def commit_count(remote, branch)
    run_git('rev-list', '--count', branch, git_dir: remote).to_i
  end

  def merge_commits(remote, branch)
    run_git('rev-list', '--merges', branch, git_dir: remote).split
  end

  def ancestor?(remote, ancestor, descendant)
    _output, status = Open3.capture2e(
      'git', "--git-dir=#{remote}", 'merge-base', '--is-ancestor', ancestor, descendant
    )
    status.success?
  end
end
