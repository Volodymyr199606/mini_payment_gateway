# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ToolResult contract' do
  describe 'to_h shape' do
    it 'includes required keys and contract_version' do
      result = Ai::Contracts::ToolResult.new(
        success: true,
        tool_name: 'get_ledger_summary',
        data: { total: 100 },
        metadata: {}
      )
      h = result.to_h
      AiContractHelpers.assert_required_keys!(
        h,
        %i[success tool_name data error error_code metadata contract_version],
        contract_name: 'ToolResult'
      )
      expect(h[:contract_version]).to eq(Ai::Contracts::TOOL_RESULT_VERSION)
    end

    it 'tool_name is always present (string)' do
      result = Ai::Contracts::ToolResult.new(success: false, tool_name: 'get_payment_intent', error_code: 'access_denied')
      h = result.to_h
      expect(h[:tool_name]).to be_a(String)
    end

    it 'from_h round-trips and preserves contract shape' do
      original = {
        success: false,
        tool_name: 'get_payment_intent',
        error_code: 'access_denied',
        authorization_denied: true,
        metadata: {},
        contract_version: '1'
      }
      obj = Ai::Contracts::ToolResult.from_h(original)
      expect(obj).to be_present
      back = obj.to_h
      expect(back[:success]).to eq(false)
      expect(back[:tool_name]).to eq('get_payment_intent')
      expect(back[:contract_version]).to be_present
    end

    it 'does not expose sensitive fields' do
      result = Ai::Contracts::ToolResult.new(success: true, tool_name: 'get_merchant_account', data: { name: 'Acme' })
      AiContractHelpers.assert_no_forbidden_keys!(result.to_h, contract_name: 'ToolResult')
    end
  end
end
