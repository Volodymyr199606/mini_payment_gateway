# frozen_string_literal: true

# Shared helpers for AI contract-level regression tests.
# Use these to assert stable keys, types, and absence of sensitive fields.
module AiContractHelpers
  # Keys that must never appear in audit or debug payloads (prompts, secrets).
  FORBIDDEN_KEYS = %w[
    prompt api_key secret password token raw_payload
    full_prompt system_prompt user_prompt
  ].freeze

  # Recursively check hash keys (string or symbol) for forbidden names.
  def self.forbidden_keys_in?(hash, prefix = '')
    return [] if hash.blank? || !hash.is_a?(Hash)

    found = []
    hash.each do |k, v|
      key_s = k.to_s.downcase
      found << "#{prefix}#{k}" if FORBIDDEN_KEYS.any? { |f| key_s.include?(f) || f.include?(key_s) }
      found.concat(forbidden_keys_in?(v, "#{prefix}#{k}.")) if v.is_a?(Hash)
      found.concat(forbidden_keys_in?(v, "#{prefix}#{k}[].")) if v.is_a?(Array) && v.any? { |e| e.is_a?(Hash) }
    end
    found
  end

  # Assert hash has all required keys (as symbols). Fails with clear message.
  def self.assert_required_keys!(hash, required_keys, contract_name: 'payload')
    hash = hash.with_indifferent_access if hash.respond_to?(:with_indifferent_access)
    missing = required_keys.map(&:to_s) - hash.keys.map(&:to_s)
    return if missing.empty?

    raise "Contract #{contract_name}: missing required keys: #{missing.sort.join(', ')}. " \
          "Present keys: #{hash.keys.map(&:to_s).sort.join(', ')}."
  end

  # Assert hash has no forbidden (sensitive) keys.
  def self.assert_no_forbidden_keys!(hash, contract_name: 'payload')
    found = forbidden_keys_in?(hash)
    return if found.empty?

    raise "Contract #{contract_name}: must not expose sensitive keys: #{found.join(', ')}."
  end

  # Assert value is one of allowed (for enums like execution_mode, composition_mode).
  def self.assert_enum!(value, allowed, contract_name:, field_name:)
    return if value.nil? || value.to_s.empty?
    return if allowed.include?(value) || allowed.include?(value.to_s)

    raise "Contract #{contract_name}: #{field_name} must be one of #{allowed.inspect}, got #{value.inspect}."
  end
end

# In specs: AiContractHelpers.assert_required_keys!(hash, keys, contract_name: '...')
#           AiContractHelpers.assert_no_forbidden_keys!(hash, contract_name: '...')
#           AiContractHelpers.assert_enum!(value, allowed, contract_name: '...', field_name: '...')
