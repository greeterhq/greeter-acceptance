# frozen_string_literal: true

RSpec.describe 'a thing' do
  it 'does one thing', requirement: 'a-requirement', scenario: 'a-scenario' do
    expect(1).to eq(2)
  end
end
