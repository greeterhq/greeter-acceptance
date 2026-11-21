# frozen_string_literal: true

require 'yaml'

# adopt-live-docs: the trace-check. It reads requirement headings from the spec
# files, the requirement/scenario tags from RSpec example files and the
# @requirement-* tags from Cucumber features, and returns one problem string per
# mismatch. It parses text only: no Node, no OpenSpec CLI.
RSpec.describe 'RepoTrace::Check' do
  let(:fixtures) { File.expand_path('fixtures/trace_check', __dir__) }
  let(:root) { File.expand_path('..', __dir__) }
  let(:alpha_specs) { "#{fixtures}/specs/alpha/spec.md" }
  let(:beta_specs) { "#{fixtures}/specs/beta/spec.md" }
  let(:in_flight) { "#{fixtures}/changes/**/specs/**/spec.md" }

  def check(**options)
    RepoTrace::Check.call(**options)
  end

  describe 'a tooling requirement' do
    it 'fails naming the requirement and the spec file when no example is tagged with it',
       requirement: 'every-requirement-has-a-verifying-test',
       scenario: 'tooling-requirement-with-no-tagged-example-fails-and-is-named' do
      problems = check(spec_glob: alpha_specs, example_glob: "#{fixtures}/examples/covered.rb")

      expect(problems).to include(
        %(requirement "uncovered-requirement" (#{alpha_specs}) has no tagged example)
      )
    end

    it 'reports nothing for a requirement that has a tagged example',
       requirement: 'every-requirement-has-a-verifying-test',
       scenario: 'tooling-requirement-with-no-tagged-example-fails-and-is-named' do
      problems = check(spec_glob: alpha_specs, example_glob: "#{fixtures}/examples/all_alpha.rb")

      expect(problems).to eq([])
    end
  end

  describe 'a greeting requirement verified by Cucumber' do
    it 'fails naming the slug, the mapped tag and the spec file when no scenario carries the tag',
       requirement: 'every-requirement-has-a-verifying-test',
       scenario: 'greeting-requirement-with-no-mapped-cucumber-tag-fails-and-is-named' do
      problems = check(spec_glob: beta_specs, example_glob: "#{fixtures}/examples/none/*.rb",
                       feature_glob: "#{fixtures}/features/mapped.feature", tag_map: "#{fixtures}/maps/ok.yml")

      expected = 'requirement "a-mapped-requirement-with-no-scenario" ' \
                 "(#{beta_specs}) maps to tag \"beta-orphan\" carried by no Cucumber scenario"
      expect(problems).to include(expected)
    end

    it 'needs no RSpec example for a requirement whose mapped tag is carried by a scenario',
       requirement: 'every-requirement-has-a-verifying-test',
       scenario: 'greeting-requirement-with-no-mapped-cucumber-tag-fails-and-is-named' do
      problems = check(spec_glob: beta_specs, example_glob: "#{fixtures}/examples/none/*.rb",
                       feature_glob: "#{fixtures}/features/mapped.feature", tag_map: "#{fixtures}/maps/ok.yml")

      expect(problems.grep(/"a-mapped-requirement"/)).to eq([])
    end
  end

  describe 'a tagged example' do
    it 'fails naming the unknown requirement slug and the example file',
       requirement: 'tagged-tests-must-match-a-requirement',
       scenario: 'unknown-requirement-slug-fails-and-is-named' do
      file = "#{fixtures}/examples/unknown_requirement.rb"
      problems = check(spec_glob: alpha_specs, example_glob: file)

      expect(problems).to include(
        %(example tagged requirement "no-such-requirement" (#{file}:3) matches no requirement heading)
      )
    end

    it 'matches a scenario slug only within its own requirement',
       requirement: 'tagged-tests-must-match-a-requirement',
       scenario: 'scenario-slug-is-matched-only-within-its-requirement' do
      wrong = "#{fixtures}/examples/wrong_scenario.rb"
      same = "#{fixtures}/examples/same_text.rb"
      problems = check(spec_glob: alpha_specs, example_glob: "{#{wrong},#{same}}")

      expect(problems).to include(
        %(example scenario "same-text" (#{wrong}:4) is not a scenario of requirement "covered-requirement")
      )
      expect(problems.grep(/same_text\.rb/)).to eq([])
    end
  end

  describe 'a requirement in a change that is not archived' do
    it 'is known when it is in an ADDED or MODIFIED section, and unknown otherwise',
       requirement: 'tagged-tests-must-match-a-requirement',
       scenario: 'requirements-in-in-flight-changes-are-known' do
      known = "#{fixtures}/examples/in_flight_known.rb"
      unknown = "#{fixtures}/examples/in_flight_unknown.rb"
      problems = check(spec_glob: alpha_specs, change_glob: in_flight, example_glob: "{#{known},#{unknown}}")

      expect(problems.grep(/in_flight_known\.rb/)).to eq([])
      expect(problems).to include(
        %(example tagged requirement "archived-only-requirement" (#{unknown}:4) matches no requirement heading),
        %(example tagged requirement "removed-requirement" (#{unknown}:7) matches no requirement heading),
        %(example tagged requirement "renamed-requirement" (#{unknown}:10) matches no requirement heading)
      )
    end

    it 'needs a tagged example for a requirement added in flight',
       requirement: 'tagged-tests-must-match-a-requirement',
       scenario: 'requirements-in-in-flight-changes-are-known' do
      problems = check(spec_glob: alpha_specs, change_glob: in_flight,
                       example_glob: "#{fixtures}/examples/covered.rb")

      expect(problems.grep(/in-flight-added-requirement/)).not_to be_empty
    end
  end

  describe 'a Cucumber requirement tag' do
    it 'fails naming the tag and the feature file when it is not in the tag map',
       requirement: 'tagged-tests-must-match-a-requirement',
       scenario: 'a-cucumber-requirement-tag-outside-the-map-fails-and-is-named' do
      feature = "#{fixtures}/features/unmapped.feature"
      problems = check(spec_glob: beta_specs, example_glob: "#{fixtures}/examples/none/*.rb",
                       feature_glob: feature, tag_map: "#{fixtures}/maps/ok.yml")

      expect(problems.grep(/tag "greeting-unmapped" \(#{Regexp.escape(feature)}\) is not in /)).not_to be_empty
    end
  end

  describe 'the tag map' do
    it 'fails naming a key that is not a requirement heading slug and the map file',
       requirement: 'the-requirement-tag-map-covers-the-greeting-headings',
       scenario: 'a-key-that-is-not-a-heading-slug-fails-and-is-named' do
      map = "#{fixtures}/maps/bad_key.yml"
      problems = check(spec_glob: beta_specs, example_glob: "#{fixtures}/examples/none/*.rb",
                       feature_glob: "#{fixtures}/features/mapped.feature", tag_map: map)

      expect(problems).to include(%(map key "no-such-heading" (#{map}) matches no requirement heading))
    end

    it 'maps each greeting heading slug to its existing Cucumber tag, and nothing else',
       requirement: 'the-requirement-tag-map-covers-the-greeting-headings',
       scenario: 'every-greeting-heading-maps-to-a-tag-that-exists' do
      expect(YAML.safe_load_file(File.join(root, 'openspec/requirement-tags.yml'))).to eq(
        'a-channel-greets-a-valid-guest' => 'greeting-happy',
        'a-channel-rejects-an-invalid-name' => 'greeting-invalid',
        'a-counting-channel-records-the-greeting-count' => 'greeting-count',
        'a-counting-channel-increments-the-count-for-a-returning-guest' => 'greeting-returning',
        'an-idempotent-replay-does-not-double-count' => 'greeting-idempotent'
      )
    end
  end

  describe 'this repository' do
    let(:problems) do
      Dir.chdir(root) do
        check(spec_glob: 'openspec/specs/**/spec.md', change_glob: 'openspec/changes/**/specs/**/spec.md',
              example_glob: 'spec/**/*.rb', exclude_glob: 'spec/fixtures/**/*',
              feature_glob: 'features/**/*.feature', tag_map: 'openspec/requirement-tags.yml')
      end
    end

    it 'has a verifying test for every requirement and no tag that matches nothing',
       requirement: 'every-requirement-has-a-verifying-test',
       scenario: 'tooling-requirement-with-no-tagged-example-fails-and-is-named' do
      expect(problems).to eq([])
    end

    it 'ties every greeting requirement to a Cucumber scenario through the tag map',
       requirement: 'the-requirement-tag-map-covers-the-greeting-headings',
       scenario: 'every-greeting-heading-maps-to-a-tag-that-exists' do
      expect(problems.grep(/greeting|requirement-tags/)).to eq([])
    end
  end
end
