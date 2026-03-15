# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dev::AiAuditsController', type: :request do
  include ApiHelpers

  describe 'GET /dev/ai_audits' do
    it 'returns 200 when dev/test environment' do
      get dev_ai_audits_path
      expect(response).to have_http_status(:ok)
    end

    it 'renders listing with empty state when no audits' do
      get dev_ai_audits_path
      expect(response.body).to include('AI Audits')
      expect(response.body).to include('No audits match')
    end

    it 'renders table and drill-down link when audits exist' do
      merchant = create_merchant_with_api_key.first
      audit = AiRequestAudit.create!(
        request_id: 'req-drill-1',
        endpoint: 'dashboard',
        agent_key: 'tool:get_payment_intent',
        merchant_id: merchant.id,
        composition_mode: 'tool_only',
        tool_used: true,
        tool_names: ['get_payment_intent'],
        success: true
      )
      get dev_ai_audits_path
      expect(response.body).to include('req-drill-1')
      expect(response.body).to include('tool:get_payment_intent')
      expect(response.body).to include(dev_ai_audit_path(audit))
    end

    it 'applies merchant_id filter' do
      merchant = create_merchant_with_api_key.first
      AiRequestAudit.create!(
        request_id: 'r1',
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id
      )
      get dev_ai_audits_path, params: { merchant_id: merchant.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('r1')
    end

    it 'applies failed_only filter' do
      AiRequestAudit.create!(
        request_id: 'fail-1',
        endpoint: 'api',
        agent_key: 'operational',
        success: false
      )
      get dev_ai_audits_path, params: { failed_only: '1' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('fail-1')
    end

    it 'does not expose prompts or secrets' do
      merchant = create_merchant_with_api_key.first
      AiRequestAudit.create!(
        request_id: 'safe-1',
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id,
        error_message: 'Something went wrong'
      )
      get dev_ai_audits_path
      body = response.body
      expect(body).not_to match(/\bprompt\b/i)
      expect(body).not_to include('sk_')
      expect(body).not_to include('pk_')
    end
  end

  describe 'GET /dev/ai_audits/:id' do
    it 'returns 200 and shows detail sections for existing audit' do
      merchant = create_merchant_with_api_key.first
      audit = AiRequestAudit.create!(
        request_id: 'detail-1',
        endpoint: 'dashboard',
        agent_key: 'tool:get_merchant_account',
        merchant_id: merchant.id,
        composition_mode: 'tool_only',
        tool_used: true,
        tool_names: ['get_merchant_account'],
        success: true,
        latency_ms: 50
      )
      get dev_ai_audit_path(audit)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('detail-1')
      expect(response.body).to include('Path summary')
      expect(response.body).to include('Request')
      expect(response.body).to include('tool_used')
      expect(response.body).to include('50')
    end

    it 'redirects to index with alert when audit not found' do
      get dev_ai_audit_path(999_999)
      expect(response).to redirect_to(dev_ai_audits_path)
      follow_redirect!
      expect(flash[:alert]).to be_present
    end

    it 'does not expose sensitive fields on detail page' do
      merchant = create_merchant_with_api_key.first
      audit = AiRequestAudit.create!(
        request_id: 'secret-check',
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id,
        error_message: 'Token expired'
      )
      get dev_ai_audit_path(audit)
      body = response.body
      expect(body).not_to include('sk_')
      expect(body).not_to include('pk_')
      expect(body).not_to match(/\bprompt\b/i)
    end
  end
end
