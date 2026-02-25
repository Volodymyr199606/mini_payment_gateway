# frozen_string_literal: true

module Ai
  # Thin wrapper for Groq API (OpenAI-compatible chat completions).
  # Configure via ENV: GROQ_API_KEY, GROQ_BASE_URL, GROQ_MODEL.
  # On model_decommissioned, retries once with next fallback model.
  class GroqClient
    DEFAULT_BASE_URL = 'https://api.groq.com/openai/v1'
    DEFAULT_MODEL = 'llama-3.3-70b-versatile'
    FALLBACK_MODELS = ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'].freeze

    def initialize(api_key: nil, base_url: nil, model: nil)
      @api_key = api_key || ENV.fetch('GROQ_API_KEY', nil)
      @base_url = (base_url || ENV.fetch('GROQ_BASE_URL', DEFAULT_BASE_URL)).chomp('/')
      @model = model || ENV.fetch('GROQ_MODEL', nil).presence || DEFAULT_MODEL
    end

    def chat(messages:, temperature: 0.3, max_tokens: 1024)
      return { content: '', error: 'GROQ_API_KEY not set', model_used: nil, fallback_used: false } if @api_key.blank?

      models_to_try = build_model_list
      last_error = nil

      models_to_try.each_with_index do |model, index|
        result = perform_request(messages: messages, temperature: temperature, max_tokens: max_tokens, model: model)
        if result[:error].nil?
          result[:model_used] = model
          result[:fallback_used] = index.positive?
          return result
        end
        last_error = result
        break unless decommissioned?(result) && index < models_to_try.length - 1
      end

      {
        content: '',
        error: last_error&.dig(:error),
        model_used: nil,
        fallback_used: false
      }
    end

    private

    def build_model_list
      primary = @model
      rest = FALLBACK_MODELS - [primary]
      [primary, *rest].uniq
    end

    def decommissioned?(result)
      return true if result[:error_code].to_s == 'model_decommissioned'
      (result[:error].to_s + result[:error_message].to_s).include?('decommissioned')
    end

    def perform_request(messages:, temperature:, max_tokens:, model:)
      body = {
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens
      }

      response = connection.post('/chat/completions') do |req|
        req.headers['Authorization'] = "Bearer #{@api_key}"
        req.headers['Content-Type'] = 'application/json'
        req.body = body.to_json
      end

      if response.success?
        content = response.body.dig('choices', 0, 'message', 'content')
        { content: content.to_s }
      else
        error_body = response.body.is_a?(Hash) ? response.body : {}
        error_code = error_body.dig('error', 'code')
        error_message = error_body.dig('error', 'message').to_s
        {
          content: '',
          error: "Groq API error: #{response.status}",
          error_code: error_code,
          error_message: error_message
        }
      end
    rescue Faraday::Error => e
      { content: '', error: "Groq request failed: #{e.message}", error_code: nil, error_message: e.message }
    end

    def connection
      @connection ||= Faraday.new(url: @base_url) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end
  end
end
