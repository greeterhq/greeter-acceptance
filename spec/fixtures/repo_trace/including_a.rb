# frozen_string_literal: true

require_relative 'shared_examples'

RSpec.describe 'fixture first including file' do
  context 'a tagged context', requirement: 'a-requirement', scenario: 'a-scenario' do
    it_behaves_like 'a shared pair'
  end
end
