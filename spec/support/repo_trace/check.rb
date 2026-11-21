# frozen_string_literal: true

require 'yaml'
require_relative 'slug'

module RepoTrace
  # Requirement and scenario headings from OpenSpec markdown, as
  # { requirement_slug => { file:, scenarios: Set } }. Main specs count every
  # heading; change deltas count only headings inside ADDED and MODIFIED
  # sections, and a MODIFIED requirement adds its scenarios to the main-spec
  # requirement of the same slug. Archived changes are skipped.
  module Headings
    REQUIREMENT = /\A### Requirement:\s*(.+?)\s*\z/
    SCENARIO = /\A#### Scenario:\s*(.+?)\s*\z/
    DELTA_SECTION = /\A## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements\s*\z/
    COUNTED_SECTIONS = %w[ADDED MODIFIED].freeze

    module_function

    def call(spec_glob:, change_glob: nil)
      known = {}
      Dir.glob(spec_glob).each { |file| read(file, known, delta: false) }
      changes = change_glob ? Dir.glob(change_glob).reject { |file| file.include?('/changes/archive/') } : []
      changes.each { |file| read(file, known, delta: true) }
      known
    end

    def read(file, known, delta:)
      state = { section: nil, current: nil }
      File.foreach(file, chomp: true) { |line| read_line(line, file, known, delta, state) }
    end

    def read_line(line, file, known, delta, state)
      section = delta && DELTA_SECTION.match(line)
      return state.update(section: section[1], current: nil) if section

      requirement = REQUIREMENT.match(line)
      return state[:current] = entry(known, requirement[1], file, delta, state) if requirement

      scenario = state[:current] && SCENARIO.match(line)
      state[:current][:scenarios] << Slug.call(scenario[1]) if scenario
    end

    # The requirement's entry when its heading counts here, else nil.
    def entry(known, heading, file, delta, state)
      return nil if delta && !COUNTED_SECTIONS.include?(state[:section])

      known[Slug.call(heading)] ||= { file: file, scenarios: Set.new }
    end
  end

  # Requirement/scenario tags read as text from RSpec files, and requirement tags
  # from Cucumber features. The files are never loaded.
  module Tags
    RspecTag = Struct.new(:requirement, :scenario, :file, :line)
    CucumberTag = Struct.new(:tag, :file)
    RSPEC_TAG = /requirement:\s*'([^']+)',\s*scenario:\s*'([^']+)'/
    CUCUMBER_TAG = /@requirement-(\S+)/

    module_function

    def rspec(files)
      files.flat_map do |file|
        text = File.read(file)
        text.to_enum(:scan, RSPEC_TAG).map do
          match = Regexp.last_match
          RspecTag.new(match[1], match[2], file, text[0...match.begin(0)].count("\n") + 1)
        end
      end
    end

    # The @requirement-* tag on any tag line of a feature.
    def cucumber(files)
      files.flat_map do |file|
        File.readlines(file, chomp: true).select { |line| line.strip.start_with?('@') }
            .flat_map { |line| line.scan(CUCUMBER_TAG).flatten }
            .map { |tag| CucumberTag.new(tag, file) }
      end
    end
  end

  # Finds requirements with no verifying test, and tags that match no
  # requirement or scenario. A requirement that is a key of the tag map is verified
  # by a Cucumber scenario carrying its mapped tag; any other needs a tagged RSpec
  # example. Text only: no Node, no OpenSpec CLI. Returns a list of problem
  # strings (empty when everything is traced).
  module Check
    module_function

    def call(spec_glob:, example_glob:, change_glob: nil, exclude_glob: nil, feature_glob: nil, tag_map: nil)
      known = Headings.call(spec_glob: spec_glob, change_glob: change_glob)
      excluded = exclude_glob ? Dir.glob(exclude_glob) : []
      map = tag_map ? YAML.safe_load_file(tag_map) : {}
      examples = Tags.rspec(files(example_glob, excluded))
      cucumber = feature_glob ? Tags.cucumber(files(feature_glob, excluded)) : []

      uncovered(known, examples, map) + map_problems(known, map, tag_map, cucumber) +
        cucumber_problems(map, tag_map, cucumber) + example_problems(known, examples)
    end

    def files(glob, excluded)
      Dir.glob(glob).reject { |file| excluded.include?(file) || File.directory?(file) }
    end

    def uncovered(known, examples, map)
      tagged = examples.map(&:requirement)
      known.except(*tagged, *map.keys)
           .map { |slug, entry| %(requirement "#{slug}" (#{entry[:file]}) has no tagged example) }
    end

    def map_problems(known, map, map_file, cucumber)
      carried = cucumber.map(&:tag)
      map.filter_map do |slug, tag|
        if !known.key?(slug)
          %(map key "#{slug}" (#{map_file}) matches no requirement heading)
        elsif !carried.include?(tag)
          %(requirement "#{slug}" (#{known[slug][:file]}) maps to tag "#{tag}" carried by no Cucumber scenario)
        end
      end
    end

    def cucumber_problems(map, map_file, cucumber)
      return [] unless map_file

      cucumber.reject { |entry| map.value?(entry.tag) }
              .map { |entry| %(tag "#{entry.tag}" (#{entry.file}) is not in #{map_file}) }
    end

    def example_problems(known, examples)
      examples.filter_map do |tag|
        where = "#{tag.file}:#{tag.line}"
        entry = known[tag.requirement]
        if entry.nil?
          %(example tagged requirement "#{tag.requirement}" (#{where}) matches no requirement heading)
        elsif tag.scenario != tag.requirement && !entry[:scenarios].include?(tag.scenario)
          %(example scenario "#{tag.scenario}" (#{where}) is not a scenario of requirement "#{tag.requirement}")
        end
      end
    end
  end
end
