# frozen_string_literal: true

RSpec.describe 'a thing' do
  it 'does one thing' do
    expect(1).to eq(1)
  end

  describe 'a group' do
    it 'does another thing' do
      expect(2).to eq(2)
    end
  end
end
