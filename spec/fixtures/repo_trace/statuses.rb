# frozen_string_literal: true

RSpec.describe 'fixture statuses' do
  it 'passes', requirement: 'a-requirement', scenario: 'a-scenario' do
    expect(1).to eq(1)
  end

  it 'fails', requirement: 'a-requirement', scenario: 'another-scenario' do
    expect(1).to eq(2)
  end

  it 'is not tagged' do
    expect(1).to eq(1)
  end
end
