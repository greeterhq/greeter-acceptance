# frozen_string_literal: true

RSpec.describe 'EventValidation' do
  let(:validation) { GreeterAcceptance::EventValidation }
  let(:environments) { GreeterAcceptance::Environments.new(environments_config) }
  let(:payload) do
    { 'channel' => 'cli', 'version' => 'v0.1.2', 'sha' => 'abc1234', 'artifact' => 'tag', 'environment' => 'prod' }
  end

  def validate(overrides = {})
    validation.validate(payload.merge(overrides), environments: environments)
  end

  describe 'a valid event' do
    it 'is returned with exactly its allowed fields' do
      expect(validate).to eq(payload)
    end

    it 'drops fields that are not allowed' do
      expect(validate('note' => 'hello')).to eq(payload)
    end

    it 'accepts a full 40-character commit identifier' do
      expect(validate('sha' => 'a' * 40)['sha']).to eq('a' * 40)
    end
  end

  describe 'the channel and environment' do
    it 'refuses an unknown channel and names it' do
      expect { validate('channel' => 'web') }.to raise_error(validation::Invalid, /channel.*web/)
    end

    it 'refuses an unknown environment and names it' do
      expect { validate('environment' => 'dev') }.to raise_error(validation::Invalid, /environment.*dev/)
    end
  end

  describe 'the version' do
    ['latest', 'v1.2', 'v1.2.3; rm -rf /', 'v1.2.3 [x](http://evil.test)', "v1.2.3\nv9.9.9"].each do |bad|
      it "refuses #{bad.inspect}" do
        expect { validate('version' => bad) }.to raise_error(validation::Invalid, /version/)
      end
    end
  end

  describe 'the commit identifier' do
    ['', 'abc', 'xyz1234', 'not-a-sha', 'abc1234; ls'].each do |bad|
      it "refuses #{bad.inspect}" do
        expect { validate('sha' => bad) }.to raise_error(validation::Invalid, /sha/)
      end
    end
  end

  describe 'required fields' do
    %w[channel version sha environment].each do |field|
      it "refuses an event with no #{field}" do
        expect { validation.validate(payload.reject { |key, _| key == field }, environments: environments) }
          .to raise_error(validation::Invalid, /#{field}/)
      end
    end
  end

  describe 'a target address' do
    %w[url base_url target address].each do |field|
      it "refuses an event carrying a #{field} field" do
        expect { validate(field => 'https://evil.test') }.to raise_error(validation::Invalid, /target address/)
      end
    end
  end
end
