# frozen_string_literal: true

module Ai
  module Generation
    # Streams chat completion chunks from Groq API (OpenAI-compatible).
    # Yields delta text chunks; returns full result on completion.
    # Never raises into caller; returns error hash on failure.
    class StreamingClient
      DEFAULT_BASE_URL = 'https://api.groq.com/openai/v1'
      DEFAULT_MODEL = 'llama-3.3-70b-versatile'
      FALLBACK_MODELS = ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'].freeze

      def initialize(api_key: nil, base_url: nil, model: nil)
        @api_key = api_key || ENV.fetch('GROQ_API_KEY', nil)
        @base_url = (base_url || ENV.fetch('GROQ_BASE_URL', DEFAULT_BASE_URL)).chomp('/')
        @model = model || ENV.fetch('GROQ_MODEL', nil).presence || DEFAULT_MODEL
      end

      # Yields each content delta; returns { content:, model_used:, fallback_used:, error: }.
      def stream(messages:, temperature: 0.3, max_tokens: 1024)
        if @api_key.blank?
          return { content: '', error: 'GROQ_API_KEY not set', model_used: nil, fallback_used: false }
        end

        models_to_try = build_model_list
        models_to_try.each_with_index do |model, index|
          result = perform_stream(messages: messages, temperature: temperature, max_tokens: max_tokens, model: model) do |delta|
            yield delta if block_given?
          end
          if result[:error].nil?
            result[:model_used] = model
            result[:fallback_used] = index.positive?
            return result
          end
          # Retry only for decommissioned models; otherwise return the actual error
          return result.merge(content: '', model_used: nil, fallback_used: index.positive?) unless decommissioned?(result) && index < models_to_try.length - 1
        end

        { content: '', error: 'Stream failed', model_used: nil, fallback_used: false }
      rescue StandardError => e
        Rails.logger.warn("[StreamingClient] stream error: #{e.class} #{e.message}")
        { content: '', error: "Stream error: #{e.message}", model_used: nil, fallback_used: false }
      end

      private

      def build_model_list
        rest = FALLBACK_MODELS - [@model]
        [@model, *rest].uniq
      end

      def decommissioned?(result)
        return true if result[:error_code].to_s == 'model_decommissioned'
        (result[:error].to_s + result[:error_message].to_s).include?('decommissioned')
      end

      def perform_stream(messages:, temperature:, max_tokens:, model:)
        uri = URI.parse("#{@base_url}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = 120
        http.open_timeout = 10

        body = {
          model: model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens,
          stream: true
        }

        req = Net::HTTP::Post.new(uri.request_uri)
        req['Authorization'] = "Bearer #{@api_key}"
        req['Content-Type'] = 'application/json'
        req.body = body.to_json

        full_content = +''

        http.request(req) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            error_body = response.body.to_s
            parsed = (JSON.parse(error_body) rescue {})
            return {
              content: '',
              error: "Groq API error: #{response.code}",
              error_code: parsed.dig('error', 'code'),
              error_message: parsed.dig('error', 'message')
            }
          end

          buffer = +''
          response.read_body do |chunk|
            buffer << chunk
            while (idx = buffer.index("\n"))
              line = buffer.slice!(0..idx).strip
              next if line.empty?
              next unless line.start_with?('data: ')

              data = line.sub(/\Adata: /, '')
              break if data == '[DONE]'

              parsed = JSON.parse(data) rescue nil
              next unless parsed

              delta = parsed.dig('choices', 0, 'delta', 'content')
              next if delta.to_s.empty?

              full_content << delta
              yield delta
            end
          end
        end

        { content: full_content }
      end
    end
  end
end
