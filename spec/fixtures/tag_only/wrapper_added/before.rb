# frozen_string_literal: true

RSpec.describe 'a driver' do
  it_behaves_like 'a shared thing', 'one'
  it_behaves_like 'a shared thing', 'two'
end
