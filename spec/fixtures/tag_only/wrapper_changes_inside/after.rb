# frozen_string_literal: true

RSpec.describe 'a driver' do
  context 'a shared thing is behaved like', requirement: 'a-requirement', scenario: 'a-scenario' do
    it_behaves_like 'a shared thing', 'one'
    it_behaves_like 'a shared thing', 'three'
  end
end
