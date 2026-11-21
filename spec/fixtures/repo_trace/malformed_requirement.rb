# frozen_string_literal: true

RSpec.describe 'fixture malformed tag' do
  it 'carries a requirement that is not a slug', requirement: 'Alice Smith', scenario: 'a-scenario' do
    expect(1).to eq(1)
  end
end
