# frozen_string_literal: true

module ApiHelpers
  def api_headers(api_key)
    {
      'X-API-KEY' => api_key,
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  # Create a merchant with API key (email/password required for model validation).
  def create_merchant_with_api_key(name: nil, email: nil)
    name ||= "Merchant #{SecureRandom.hex(4)}"
    email ||= "test_#{SecureRandom.hex(4)}@example.com"
    Merchant.create_with_api_key(
      name: name,
      status: 'active',
      email: email,
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  # Stub processor simulations so tests get deterministic success.
  # Uses built-in RSpec; no external API dependency in tests.
  def stub_processor_success
    adapter = instance_double(
      Payments::Providers::BaseAdapter,
      fetch_status: Payments::ProviderResult.new(success: true, provider_status: 'ok'),
      verify_webhook_signature: true
    )

    allow(adapter).to receive(:authorize) do
      Payments::ProviderResult.new(success: true, processor_ref: "sim_auth_#{SecureRandom.hex(8)}")
    end
    allow(adapter).to receive(:capture) do
      Payments::ProviderResult.new(success: true, processor_ref: "sim_cap_#{SecureRandom.hex(8)}")
    end
    allow(adapter).to receive(:void) do
      Payments::ProviderResult.new(success: true, processor_ref: "sim_void_#{SecureRandom.hex(8)}")
    end
    allow(adapter).to receive(:refund) do
      Payments::ProviderResult.new(success: true, processor_ref: "sim_ref_#{SecureRandom.hex(8)}")
    end

    allow(adapter).to receive(:normalize_webhook_event) do |payload:, headers:|
      {
        event_type: payload['event_type'],
        merchant_id: payload.dig('data', 'merchant_id'),
        payload: payload,
        signature: headers['X-WEBHOOK-SIGNATURE']
      }
    end

    allow(Payments::ProviderRegistry).to receive(:current).and_return(adapter)
  end

  # Prevent webhook delivery from running in tests (avoids HTTP calls).
  # Tests adapt to current behavior; no app changes.
  def stub_webhook_delivery
    allow(WebhookDeliveryJob).to receive(:perform_later)
  end
end
