# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dev::AiHealthController', type: :request do
  include ApiHelpers

  describe 'GET /dev/ai_health' do
    it 'returns 200 when dev/test environment' do
      get dev_ai_health_path
      expect(response).to have_http_status(:ok)
    end

    it 'renders health page with overall status and metric statuses' do
      get dev_ai_health_path
      expect(response.body).to include('AI Health')
      expect(response.body).to include('Overall status')
      expect(response.body).to include('healthy')
      expect(response.body).to include('Metric statuses')
      expect(response.body).to include('Metrics by time window')
      expect(response.body).to include('Recent anomalies')
    end

    it 'renders RAG corpus section with corpus_version and docs_count' do
      get dev_ai_health_path
      expect(response.body).to include('RAG corpus')
      expect(response.body).to include('corpus_version')
      expect(response.body).to include('docs_count')
    end

    it 'accepts merchant_id filter' do
      merchant = create_merchant_with_api_key.first
      get dev_ai_health_path, params: { merchant_id: merchant.id }
      expect(response).to have_http_status(:ok)
    end

    it 'returns JSON when format is json' do
      get dev_ai_health_path, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to include('application/json')
      json = response.parsed_body
      expect(json).to have_key('overall_status')
      expect(json).to have_key('metric_statuses')
      expect(json).to have_key('recent_anomalies')
      expect(json).to have_key('time_windows')
    end
  end
end
