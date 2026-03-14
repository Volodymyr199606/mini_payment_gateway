# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dev::AiAnalyticsController', type: :request do
  include ApiHelpers
  describe 'GET /dev/ai_analytics' do
    it 'returns 200 when dev environment' do
      get dev_ai_analytics_path
      expect(response).to have_http_status(:ok)
    end

    it 'renders analytics page with empty state when no audits' do
      get dev_ai_analytics_path
      expect(response.body).to include('AI Analytics')
      expect(response.body).to include('No AI audit records')
    end

    it 'renders metrics when audits exist' do
      merchant = create_merchant_with_api_key.first
      AiRequestAudit.create!(
        request_id: 'req-1',
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id
      )
      get dev_ai_analytics_path
      expect(response.body).to include('Total Requests')
      expect(response.body).to include('1')
    end

    it 'accepts period filter' do
      get dev_ai_analytics_path, params: { period: '30d' }
      expect(response).to have_http_status(:ok)
    end

    it 'accepts merchant_id filter' do
      merchant = Merchant.create!(name: 'M', email: 'm@x.com')
      get dev_ai_analytics_path, params: { merchant_id: merchant.id }
      expect(response).to have_http_status(:ok)
    end

    it 'does not expose sensitive fields' do
      merchant = create_merchant_with_api_key.first
      AiRequestAudit.create!(
        request_id: 'req-1',
        endpoint: 'dashboard',
        agent_key: 'operational',
        merchant_id: merchant.id,
        error_message: 'Something went wrong'
      )
      get dev_ai_analytics_path
      body = response.body
      expect(body).not_to include('error_message')
      expect(body).not_to include('parsed_entities')
      expect(body).not_to include('parsed_intent_hints')
    end
  end
end
