# frozen_string_literal: true

require 'faraday'
require 'openssl'

module Payments
  module Providers
    class StripeAdapter < BaseAdapter
      SIGNATURE_TOLERANCE_SECONDS = 300

      def authorize(payment_intent:)
        response = stripe_post('/v1/payment_intents', {
          amount: payment_intent.amount_cents,
          currency: payment_intent.currency.to_s.downcase,
          capture_method: 'manual',
          confirm: true,
          payment_method: stripe_payment_method_id_for(payment_intent),
          metadata: {
            merchant_id: payment_intent.merchant_id,
            internal_payment_intent_id: payment_intent.id
          }
        })

        status = response['status'].to_s
        success = %w[requires_capture succeeded].include?(status)
        result_for(
          success: success,
          processor_ref: response['id'],
          provider_status: status,
          failure_code: response['last_payment_error']&.dig('code') || 'authorization_failed',
          failure_message: response['last_payment_error']&.dig('message') || 'Authorization failed'
        )
      end

      def capture(payment_intent:)
        provider_payment_intent_id = provider_payment_intent_id_for(payment_intent)
        return missing_reference_result('capture') if provider_payment_intent_id.blank?

        response = stripe_post("/v1/payment_intents/#{provider_payment_intent_id}/capture", {})
        status = response['status'].to_s
        success = (status == 'succeeded')
        result_for(
          success: success,
          processor_ref: response['id'],
          provider_status: status,
          failure_code: response['last_payment_error']&.dig('code') || 'capture_failed',
          failure_message: response['last_payment_error']&.dig('message') || 'Capture failed'
        )
      end

      def void(payment_intent:)
        provider_payment_intent_id = provider_payment_intent_id_for(payment_intent)
        return missing_reference_result('void') if provider_payment_intent_id.blank?

        response = stripe_post("/v1/payment_intents/#{provider_payment_intent_id}/cancel", {})
        status = response['status'].to_s
        success = (status == 'canceled')
        result_for(
          success: success,
          processor_ref: response['id'],
          provider_status: status,
          failure_code: 'void_failed',
          failure_message: 'Void failed'
        )
      end

      def refund(payment_intent:, amount_cents:)
        provider_payment_intent_id = provider_payment_intent_id_for(payment_intent)
        return missing_reference_result('refund') if provider_payment_intent_id.blank?

        response = stripe_post('/v1/refunds', {
          payment_intent: provider_payment_intent_id,
          amount: amount_cents,
          metadata: {
            merchant_id: payment_intent.merchant_id,
            internal_payment_intent_id: payment_intent.id
          }
        })

        status = response['status'].to_s
        success = (status == 'succeeded')
        result_for(
          success: success,
          processor_ref: response['id'],
          provider_status: status,
          failure_code: response['failure_reason'] || 'refund_failed',
          failure_message: response['failure_reason'] || 'Refund failed'
        )
      end

      def fetch_status(payment_intent:)
        provider_payment_intent_id = provider_payment_intent_id_for(payment_intent)
        return missing_reference_result('status') if provider_payment_intent_id.blank?

        response = stripe_get("/v1/payment_intents/#{provider_payment_intent_id}")
        ProviderResult.new(
          success: true,
          processor_ref: response['id'],
          provider_status: response['status']
        )
      end

      def verify_webhook_signature(payload:, headers:)
        signature_header = header_value(headers, 'Stripe-Signature').to_s
        return false if signature_header.blank?

        timestamp, signatures = parse_signature_header(signature_header)
        return false if timestamp.nil? || signatures.empty?
        return false if (Time.now.to_i - timestamp).abs > SIGNATURE_TOLERANCE_SECONDS

        signed_payload = "#{timestamp}.#{payload}"
        expected = OpenSSL::HMAC.hexdigest('SHA256', Payments::Config.stripe_webhook_secret, signed_payload)
        signatures.any? { |sig| ActiveSupport::SecurityUtils.secure_compare(expected, sig) }
      rescue StandardError
        false
      end

      def normalize_webhook_event(payload:, headers:)
        type = payload['type'].to_s
        data_object = payload.dig('data', 'object') || {}
        metadata = data_object['metadata'] || {}

        internal_event_type =
          case type
          when 'payment_intent.succeeded' then 'transaction.succeeded'
          when 'payment_intent.payment_failed' then 'transaction.failed'
          when 'charge.dispute.created' then 'chargeback.opened'
          else
            type
          end

        {
          event_type: internal_event_type,
          merchant_id: metadata['merchant_id'],
          payload: {
            provider: 'stripe',
            provider_type: type,
            id: payload['id'],
            created: payload['created'],
            data: {
              merchant_id: metadata['merchant_id'],
              payment_intent_id: metadata['internal_payment_intent_id'] || data_object['payment_intent'],
              provider_payment_intent_id: data_object['id'],
              object: data_object
            }
          },
          signature: header_value(headers, 'Stripe-Signature'),
          provider_event_id: payload['id']
        }
      end

      private

      def result_for(success:, processor_ref:, provider_status:, failure_code:, failure_message:)
        if success
          ProviderResult.new(success: true, processor_ref: processor_ref, provider_status: provider_status)
        else
          ProviderResult.new(
            success: false,
            processor_ref: processor_ref,
            provider_status: provider_status,
            failure_code: failure_code,
            failure_message: failure_message
          )
        end
      end

      def missing_reference_result(kind)
        ProviderResult.new(
          success: false,
          failure_code: 'missing_processor_reference',
          failure_message: "Cannot #{kind} without provider payment intent reference"
        )
      end

      def stripe_payment_method_id_for(payment_intent)
        payment_intent.payment_method&.token.presence || 'pm_card_visa'
      end

      def provider_payment_intent_id_for(payment_intent)
        payment_intent.transactions.where(kind: 'authorize', status: 'succeeded').order(created_at: :desc).pick(:processor_ref)
      end

      def parse_signature_header(header)
        pairs = header.split(',').map { |part| part.split('=', 2) }.select { |pair| pair.size == 2 }
        timestamp = pairs.find { |k, _| k == 't' }&.last&.to_i
        signatures = pairs.select { |k, _| k == 'v1' }.map(&:last)
        [timestamp, signatures]
      end

      def stripe_get(path)
        response = client.get(path)
        parse_response(response)
      end

      def stripe_post(path, params)
        response = client.post(path) { |req| req.body = URI.encode_www_form(flatten_params(params)) }
        parse_response(response)
      end

      def parse_response(response)
        parsed = JSON.parse(response.body)
        return parsed if response.status.between?(200, 299)

        message = parsed.dig('error', 'message') || 'Stripe request failed'
        raise ProviderRequestError, "Stripe API error (status=#{response.status}): #{message}"
      rescue JSON::ParserError
        raise ProviderRequestError, "Stripe API returned invalid JSON (status=#{response.status})"
      end

      def client
        @client ||= Faraday.new(url: Payments::Config.stripe_base_url) do |faraday|
          faraday.request :url_encoded
          faraday.adapter Faraday.default_adapter
          faraday.headers['Authorization'] = "Bearer #{Payments::Config.stripe_api_key}"
          faraday.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        end
      end

      def flatten_params(params, prefix = nil)
        params.each_with_object({}) do |(key, value), out|
          full_key = prefix ? "#{prefix}[#{key}]" : key.to_s
          if value.is_a?(Hash)
            out.merge!(flatten_params(value, full_key))
          else
            out[full_key] = value
          end
        end
      end

      def header_value(headers, key)
        headers[key] || headers[key.downcase] || headers[key.upcase]
      end
    end
  end
end
