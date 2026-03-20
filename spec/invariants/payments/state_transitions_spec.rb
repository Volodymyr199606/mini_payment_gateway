# frozen_string_literal: true

# State transition invariants: valid lifecycle transitions and rejection of invalid ones.
# Protects PaymentIntent status machine from drift.
require 'rails_helper'

RSpec.describe 'Payment invariants: state transitions', :invariants do
  before { stub_successful_provider }

  # Valid transitions per PAYMENT_LIFECYCLE.md
  VALID_TRANSITIONS = {
    'created' => { authorize: true, capture: false, void: true, refund: false },
    'authorized' => { authorize: false, capture: true, void: true, refund: false },
    'captured' => { authorize: false, capture: false, void: false, refund: true },
    'canceled' => { authorize: false, capture: false, void: false, refund: false },
    'failed' => { authorize: false, capture: false, void: false, refund: false }
  }.freeze

  VALID_TRANSITIONS.each do |from_status, ops|
    ops.each do |op, should_succeed|
      it "#{from_status} → #{op}: #{should_succeed ? 'allowed' : 'rejected'}" do
        pi = build_payment_intent(merchant: build_merchant, status: from_status)
        service = case op
                  when :authorize then AuthorizeService.call(payment_intent: pi)
                  when :capture then CaptureService.call(payment_intent: pi)
                  when :void then VoidService.call(payment_intent: pi)
                  when :refund then RefundService.call(payment_intent: pi)
                  end

        if should_succeed
          expect(service).to be_success,
            "Expected #{op} from #{from_status} to succeed, but got errors: #{service.errors.inspect}"
        else
          expect(service).not_to be_success,
            "Expected #{op} from #{from_status} to be rejected, but it succeeded"
        end
      end
    end
  end
end
