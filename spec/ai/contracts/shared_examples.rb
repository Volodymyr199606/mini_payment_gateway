# frozen_string_literal: true

# Shared examples for AI contract regression tests.
# Usage: include_examples 'has stable contract keys', hash, %i[key1 key2]
#        include_examples 'includes schema_version', hash
#        include_examples 'does not expose sensitive fields', hash, 'DebugPayload'
RSpec.shared_examples 'has stable contract keys' do |payload, required_keys|
  it 'includes all required contract keys' do
    h = payload.respond_to?(:to_h) ? payload.to_h : payload
    h = h.with_indifferent_access if h.respond_to?(:with_indifferent_access)
    required_keys.each do |key|
      expect(h).to have_key(key), "Expected contract to have key #{key.inspect}. Keys: #{h.keys.map(&:inspect).join(', ')}"
    end
  end
end

RSpec.shared_examples 'includes version key' do |payload, version_key = :contract_version|
  it "includes #{version_key}" do
    h = payload.respond_to?(:to_h) ? payload.to_h : payload
    h = h.with_indifferent_access if h.respond_to?(:with_indifferent_access)
    expect(h).to have_key(version_key), "Expected contract to have #{version_key}. Keys: #{h.keys.map(&:inspect).join(', ')}"
    expect(h[version_key]).to be_present, "Expected #{version_key} to be non-blank"
  end
end

RSpec.shared_examples 'does not expose sensitive fields' do |payload, contract_name = 'payload'|
  it 'does not contain prompt, api_key, or other sensitive keys' do
    h = payload.respond_to?(:to_h) ? payload.to_h : payload
    found = AiContractHelpers.forbidden_keys_in?(h)
    expect(found).to be_empty, "#{contract_name} must not expose sensitive keys: #{found.join(', ')}"
  end
end

RSpec.shared_examples 'supports to_h shape' do |factory_proc|
  it 'serializes to a hash with stable keys' do
    obj = factory_proc.call
    h = obj.to_h
    expect(h).to be_a(Hash)
    expect(h.keys).to all(be_a(Symbol).or(be_a(String)))
  end
end
