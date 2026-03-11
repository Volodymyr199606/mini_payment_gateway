# frozen_string_literal: true

module Ai
  module ScenarioEntityFactory
    # Creates domain records for scenario entity_refs and returns id mapping for message substitution.
    # Call with (scenario, merchant_id) -> { payment_intent_id: 1, transaction_id: 2, webhook_event_id: 3 }
    def self.call(scenario, merchant_id)
      refs = Array(scenario[:entity_refs]).map(&:to_s)
      return {} if refs.empty?

      ids = {}
      merchant = Merchant.find_by(id: merchant_id)
      return ids unless merchant

      refs.each do |ref|
        case ref
        when 'payment_intent'
          ids[:payment_intent_id] ||= create_payment_intent(merchant)
        when 'transaction'
          pi_id = ids[:payment_intent_id] || create_payment_intent(merchant)
          ids[:payment_intent_id] = pi_id
          ids[:transaction_id] = create_transaction(merchant, pi_id)
        when 'webhook_event'
          ids[:webhook_event_id] = create_webhook_event(merchant)
        end
      end
      ids
    end

    def self.create_payment_intent(merchant)
        customer = merchant.customers.first || merchant.customers.create!(
        email: "scenario_#{SecureRandom.hex(4)}@example.com"
      )
      merchant.payment_intents.create!(
        customer_id: customer.id,
        amount_cents: 1000,
        currency: 'USD'
      ).id
    end

    def self.create_transaction(merchant, payment_intent_id)
      pi = merchant.payment_intents.find(payment_intent_id)
      pi.transactions.create!(
        kind: 'capture',
        status: 'succeeded',
        amount_cents: 1000,
        processor_ref: "txn_scenario_#{SecureRandom.hex(8)}"
      ).id
    end

    def self.create_webhook_event(merchant)
      merchant.webhook_events.create!(
        event_type: 'payment_intent.captured',
        payload: { 'id' => 'evt_1', 'type' => 'payment_intent.captured' },
        delivery_status: 'succeeded',
        attempts: 1
      ).id
    end
  end
end
