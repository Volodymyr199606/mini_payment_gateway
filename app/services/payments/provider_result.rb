# frozen_string_literal: true

module Payments
  # Unified adapter result consumed by payment domain services.
  class ProviderResult
    attr_reader :processor_ref, :failure_code, :failure_message, :provider_status, :event_type, :event_payload

    def initialize(success:, processor_ref: nil, failure_code: nil, failure_message: nil, provider_status: nil, event_type: nil, event_payload: nil)
      @success = !!success
      @processor_ref = processor_ref
      @failure_code = failure_code
      @failure_message = failure_message
      @provider_status = provider_status
      @event_type = event_type
      @event_payload = event_payload
    end

    def success?
      @success
    end
  end
end
