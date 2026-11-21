# frozen_string_literal: true

# adopt-live-docs: tagging existing specs may change them in exactly one way. Tag
# pairs (`requirement:`/`scenario:`), whitespace, and tagged `context` wrappers
# around otherwise unchanged lines are allowed. Any other change, in any file, is a
# problem. RepoTrace::TagOnlyDiff.call(path:, before:, after:) returns problem
# strings naming `path` (an empty array when the change is allowed).
RSpec.describe 'RepoTrace::TagOnlyDiff' do
  def diff(case_name, path: 'spec/example_spec.rb')
    dir = File.join(File.expand_path('fixtures/tag_only', __dir__), case_name)
    RepoTrace::TagOnlyDiff.call(path: path, before: File.read(File.join(dir, 'before.rb')),
                                after: File.read(File.join(dir, 'after.rb')))
  end

  it 'allows tag pairs added to it and describe lines, wrapped or not' do
    expect(diff('tags_added')).to eq([])
  end

  it 'fails when an assertion changes, naming the file' do
    problems = diff('assertion_changed', path: 'spec/changed_spec.rb')

    expect(problems).not_to be_empty
    expect(problems).to all(include('spec/changed_spec.rb'))
  end

  it 'allows a tagged context wrapped around lines that are otherwise unchanged' do
    expect(diff('wrapper_added')).to eq([])
  end

  it 'fails when a line inside a new wrapper also changes' do
    problems = diff('wrapper_changes_inside', path: 'spec/wrapped_spec.rb')

    expect(problems).not_to be_empty
    expect(problems).to all(include('spec/wrapped_spec.rb'))
  end

  it 'fails for any other change, such as one to spec/spec_helper.rb' do
    problems = diff('other_file_change', path: 'spec/spec_helper.rb')

    expect(problems).not_to be_empty
    expect(problems).to all(include('spec/spec_helper.rb'))
  end
end
