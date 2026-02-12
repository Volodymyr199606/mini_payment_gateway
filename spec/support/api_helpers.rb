# frozen_string_literal: true

module ApiHelpers
  def api_headers(api_key)
    {
      'X-API-KEY' => api_key,
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  # Stub processor simulations so tests get deterministic success.
  # Uses built-in RSpec; no new gems. Stubs private methods on service instances.
  def stub_processor_success
    allow_any_instance_of(AuthorizeService).to receive(:simulate_processor_authorization).and_return(true)
    allow_any_instance_of(CaptureService).to receive(:simulate_processor_capture).and_return(true)
    allow_any_instance_of(VoidService).to receive(:simulate_processor_void).and_return(true)
    allow_any_instance_of(RefundService).to receive(:simulate_processor_refund).and_return(true)
  end

  # Prevent webhook delivery from running in tests (avoids HTTP calls).
  # Tests adapt to current behavior; no app changes.
  def stub_webhook_delivery
    allow(WebhookDeliveryJob).to receive(:perform_later)
  end
end
