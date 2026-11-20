# frozen_string_literal: true

RSpec.describe 'fixture skip and pending' do
  it 'is skipped', requirement: 'a-requirement', scenario: 'skipped-scenario', skip: 'not yet' do
    expect(1).to eq(2)
  end

  it 'is pending', requirement: 'a-requirement', scenario: 'pending-scenario' do
    pending 'not yet'
    expect(1).to eq(2)
  end
end
