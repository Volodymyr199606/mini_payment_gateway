# frozen_string_literal: true

module Ai
  module Rag
    # OpenAI-compatible embeddings API. Configure via ENV: EMBEDDING_API_KEY (or OPENAI_API_KEY), EMBEDDING_BASE_URL, EMBEDDING_MODEL.
    # Returns array of 1536 floats per text (model-dependent).
    class EmbeddingClient
      DEFAULT_BASE_URL = 'https://api.openai.com/v1'
      DEFAULT_MODEL = 'text-embedding-3-small'
      DIMENSIONS = 1536

      def initialize(api_key: nil, base_url: nil, model: nil)
        @api_key = api_key || ENV.fetch('EMBEDDING_API_KEY', nil) || ENV.fetch('OPENAI_API_KEY', nil)
        @base_url = (base_url || ENV.fetch('EMBEDDING_BASE_URL', DEFAULT_BASE_URL)).chomp('/')
        @model = (model || ENV.fetch('EMBEDDING_MODEL', nil)).presence || DEFAULT_MODEL
      end

      # Returns array of floats (length DIMENSIONS) or nil on error.
      def embed(text)
        return nil if @api_key.blank? || text.blank?

        body = { input: text.to_s.strip, model: @model }
        resp = connection.post('/embeddings', body.to_json, 'Content-Type' => 'application/json')
        return nil unless resp.status == 200

        data = JSON.parse(resp.body)
        data.dig('data', 0, 'embedding')&.map(&:to_f)
      rescue Faraday::Error, JSON::ParserError
        nil
      end

      private

      def connection
        @connection ||= Faraday.new(url: @base_url) do |f|
          f.request :authorization, 'Bearer', @api_key
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
