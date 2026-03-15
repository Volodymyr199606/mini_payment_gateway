# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dev::AiAuditsController replay', type: :request do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  describe 'POST /dev/ai_audits/:id/replay' do
    it 'redirects to audit show with replay result when replay runs' do
      audit = AiRequestAudit.create!(
        request_id: 'replay-ctrl-1',
        endpoint: 'dashboard',
        agent_key: 'tool:get_merchant_account',
        merchant_id: merchant.id,
        tool_used: true,
        tool_names: ['get_merchant_account']
      )
      post dev_replay_ai_audit_path(audit)
      expect(response).to redirect_to(dev_ai_audit_path(audit))
      follow_redirect!
      expect(response.body).to include('Replay comparison')
      expect(response.body).to include('Original summary')
      expect(response.body).to include('Replay summary')
    end

    it 'redirects to list with alert when audit not found' do
      post dev_replay_ai_audit_path(-1)
      expect(response).to redirect_to(dev_ai_audits_path)
      follow_redirect!
      expect(flash[:alert]).to be_present
    end

    it 'does not expose prompts or secrets in replay comparison' do
      audit = AiRequestAudit.create!(
        request_id: 'secret-check',
        endpoint: 'dashboard',
        agent_key: 'tool:get_merchant_account',
        merchant_id: merchant.id,
        tool_used: true,
        tool_names: ['get_merchant_account']
      )
      post dev_replay_ai_audit_path(audit)
      follow_redirect!
      body = response.body
      expect(body).not_to include('sk_')
      expect(body).not_to include('pk_')
      expect(body).not_to match(/\bprompt\b/i)
    end
  end
end
