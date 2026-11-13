# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# The script's `$PROGRAM_NAME == __FILE__` guard keeps the CLI from running, so
# loading it only defines the CliRelease module.
load File.expand_path('../bin/cli-release', __dir__)

# fix-candidate-ruby-version: CliRelease.ruby_version translates the Ruby
# requirement in an artifact's Gemfile into a value ruby/setup-ruby accepts, or
# fails closed (design.md, "Translation rules" and "Security Considerations").
RSpec.describe 'CliRelease.ruby_version' do
  let(:dir) { Dir.mktmpdir('cli-release-spec') }
  let(:gemfile) { File.join(dir, 'Gemfile') }
  let(:failure) { CliRelease::Failure }
  let(:script) { File.expand_path('../bin/cli-release', __dir__) }

  after { FileUtils.remove_entry(dir) }

  def write_gemfile(body)
    File.write(gemfile, "source 'https://rubygems.org'\n#{body}\n")
  end

  def version_for(body)
    write_gemfile(body)
    CliRelease.ruby_version(dir)
  end

  describe 'a requirement it can translate' do
    {
      "ruby '3.3.5'" => '3.3.5',
      "ruby '= 3.3.5'" => '3.3.5',
      "ruby '=3.3.5'" => '3.3.5',
      "ruby '~> 3.3.5'" => '3.3',
      "ruby '~>3.3.5'" => '3.3',
      "ruby '~> 3.3'" => '3.3',
      "ruby '>= 3.3.5'" => '3.3',
      "ruby '>=3.3'" => '3.3',
      "ruby('3.3.5')" => '3.3.5',
      "ruby ( '3.3.5' )" => '3.3.5',
      'ruby "3.3.5"' => '3.3.5',
      "ruby '3.3.5'   " => '3.3.5',
      "  ruby '3.3.5'" => '3.3.5',
      "ruby '3.3.5' # pin" => '3.3.5',
      "ruby('~> 3.3.5') # series" => '3.3'
    }.each do |line, expected|
      it "translates #{line.inspect} to #{expected}" do
        expect(version_for(line)).to eq(expected)
      end
    end
  end

  describe 'no requirement' do
    it 'is nil when the Gemfile has no ruby line' do
      expect(version_for("gem 'greeter-core', '~> 0.1'")).to be_nil
    end

    it 'is nil when the only ruby line is commented out' do
      expect(version_for("# ruby '3.3.5'\n  # ruby '~> 3.3.5'")).to be_nil
    end

    it 'does not count a line that only starts with the word ruby' do
      expect(version_for("ruby_version = '3.3'")).to be_nil
    end
  end

  describe 'a requirement it refuses' do
    [
      "ruby '3.3'",
      "ruby '= 3.3'",
      "ruby '< 4'",
      "ruby '~> 3'",
      "ruby '>= 3.3', '< 3.5'",
      "ruby '3.3.5', engine: 'jruby'",
      "ruby file: '.ruby-version'",
      "ruby '3.3.5p100'",
      "ruby '3.3; rm -rf /'"
    ].each do |line|
      it "refuses #{line.inspect} and names the line" do
        expect { version_for(line) }
          .to raise_error(failure, "unsupported ruby requirement in Gemfile: #{line}")
      end
    end

    it 'refuses a Gemfile with two ruby lines, naming the second' do
      expect { version_for("ruby '3.3.5'\nruby '3.3.6'") }
        .to raise_error(failure, "unsupported ruby requirement in Gemfile: ruby '3.3.6'")
    end
  end

  describe 'the line it names' do
    def refusal_for(body)
      version_for(body)
      nil
    rescue CliRelease::Failure => e
      e.message
    end

    it 'replaces a tab and an escape character with ? and stays on one line' do
      message = refusal_for("ruby '3.3\t\e[31m'")

      expect(message).to eq("unsupported ruby requirement in Gemfile: ruby '3.3??[31m'")
      expect(message.lines.size).to eq(1)
    end

    it 'replaces a bidirectional override with ?' do
      expect(refusal_for("ruby '3.3\u202E5'"))
        .to eq("unsupported ruby requirement in Gemfile: ruby '3.3?5'")
    end

    it 'truncates the line to 80 characters' do
      line = "ruby '< #{'9' * 200}'"
      message = refusal_for(line)

      expect(message).to eq("unsupported ruby requirement in Gemfile: #{line[0, 80]}")
    end
  end

  describe 'a Gemfile it will not read' do
    it 'refuses a Gemfile that is a symbolic link, without reading its target' do
      File.write(File.join(dir, 'Gemfile.real'), "ruby '~> 3.3.5'\n")
      File.symlink(File.join(dir, 'Gemfile.real'), gemfile)

      expect { CliRelease.ruby_version(dir) }.to raise_error(failure, 'Gemfile is not a regular file')
    end

    it 'refuses a Gemfile that is a named pipe, without waiting on it' do
      File.mkfifo(gemfile)
      reader = Thread.new do
        CliRelease.ruby_version(dir)
      rescue CliRelease::Failure => e
        e
      end
      finished = reader.join(2)
      # Release a reader stuck in open(2) so a regression fails instead of hanging.
      File.open(gemfile, File::WRONLY | File::NONBLOCK, &:close) unless finished
      reader.join

      expect(finished).not_to be_nil, 'ruby_version blocked waiting on the named pipe'
      expect(reader.value).to be_a(failure).and(have_attributes(message: 'Gemfile is not a regular file'))
    end

    it 'refuses a Gemfile larger than 64 KiB' do
      body = "ruby '3.3.5'\n"
      File.write(gemfile, body + ('#' * (65_537 - body.bytesize)))

      expect { CliRelease.ruby_version(dir) }.to raise_error(failure, 'Gemfile is larger than 64 KiB')
    end

    it 'reads a Gemfile of exactly 64 KiB' do
      body = "ruby '3.3.5'\n"
      File.write(gemfile, body + ('#' * (65_536 - body.bytesize)))

      expect(CliRelease.ruby_version(dir)).to eq('3.3.5')
    end

    it 'refuses a Gemfile that is not valid UTF-8, echoing none of its bytes' do
      File.binwrite(gemfile, "ruby '3.3.5'\n# \xFF\xFE\n".b)

      expect { CliRelease.ruby_version(dir) }.to raise_error(failure, 'Gemfile is not valid UTF-8')
    end
  end

  describe 'the ruby-version command' do
    def run_script(body)
      write_gemfile(body)
      Open3.capture3(RbConfig.ruby, script, 'ruby-version', dir)
    end

    it 'prints the translated version and exits 0' do
      stdout, _stderr, status = run_script("ruby '~> 3.3.5'")

      expect(stdout).to eq("3.3\n")
      expect(status.exitstatus).to eq(0)
    end

    it 'exits 1 with the refusal on stderr and prints nothing on stdout' do
      stdout, stderr, status = run_script("ruby '< 4'")

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("bin/cli-release: unsupported ruby requirement in Gemfile: ruby '< 4'")
      expect(stdout).to be_empty
    end
  end
end
