# frozen_string_literal: true

RSpec.describe 'greeting Alice Smith' do
  it 'greets Alice Smith', requirement: 'a-requirement', scenario: 'a-scenario' do
    expect('Alice Smith').to eq('Alice Smith')
  end

  it 'fails for Alice Smith', requirement: 'a-requirement', scenario: 'another-scenario' do
    expect('Alice Smith').to eq('Bob Jones')
  end
end
