# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Policy::Decision contract' do
  describe 'to_h shape' do
    it 'always includes allowed and has stable keys' do
      allow_decision = Ai::Policy::Decision.allow(decision_type: :tool, metadata: {})
      deny_decision = Ai::Policy::Decision.deny(reason_code: 'merchant_required', decision_type: :orchestration)

      [allow_decision, deny_decision].each do |d|
        h = d.to_h
        AiContractHelpers.assert_required_keys!(h, %i[allowed], contract_name: 'Policy::Decision')
        expect(h[:allowed]).to be_in([true, false])
        expect(h).to have_key(:decision_type)
        expect(h).to have_key(:metadata)
        expect(h[:metadata]).to be_a(Hash)
      end
    end

    it 'deny includes reason_code and optional safe_message' do
      d = Ai::Policy::Decision.deny(reason_code: 'record_not_owned', safe_message: 'Could not fetch data.')
      h = d.to_h
      expect(h[:reason_code]).to be_present
      expect(h[:safe_message].nil? || h[:safe_message].is_a?(String)).to be true
    end

    it 'does not expose sensitive fields' do
      d = Ai::Policy::Decision.deny(reason_code: 'test', metadata: { tool_name: 'get_payment_intent' })
      AiContractHelpers.assert_no_forbidden_keys!(d.to_h, contract_name: 'Policy::Decision')
    end
  end
end
