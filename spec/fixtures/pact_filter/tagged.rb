# frozen_string_literal: true

# add-pact-consumer: one :pact example outside spec/pact/, so the pact gem's own
# path-based filter never applies and only spec_helper's exclusion can skip it.
# spec/ci_workflow_spec.rb runs this file with and without `-t pact`.
RSpec.describe 'a pact-tagged fixture', :pact do
  it 'runs only when the pact tag is selected' do
    expect(true).to be(true)
  end
end
