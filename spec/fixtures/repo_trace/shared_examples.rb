# frozen_string_literal: true

RSpec.shared_examples 'a shared pair' do
  it 'passes' do
    expect(1).to eq(1)
  end

  it 'fails' do
    expect(1).to eq(2)
  end
end
