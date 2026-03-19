# frozen_string_literal: true

module MiniPaymentGatewayPerf
  # Deterministic merchant + payment graph for perf scenarios (development-safe).
  class World
    attr_reader :merchant, :api_key, :email, :password, :customer, :payment_method

    def self.build!(tag: 'perf')
      new(tag: tag).tap(&:ensure_records!)
    end

    def initialize(tag: 'perf')
      @tag = tag
      @email = "perf_#{tag}_#{SecureRandom.hex(4)}@example.com"
      @password = 'perf_Password123!'
    end

    def ensure_records!
      @merchant, @api_key = Merchant.create_with_api_key(
        name: "Perf Merchant #{@tag}",
        status: 'active',
        email: @email,
        password: @password,
        password_confirmation: @password
      )
      @customer = Customer.create!(merchant: @merchant, email: "cust_#{SecureRandom.hex(4)}@example.com")
      @payment_method = PaymentMethod.create!(
        customer: @customer,
        method_type: 'card',
        last4: '4242',
        brand: 'Visa',
        exp_month: 12,
        exp_year: 2030
      )
      self
    end

    def api_headers
      {
        'X-API-KEY' => @api_key,
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def create_intent!(status: 'created', amount_cents: 5000)
      PaymentIntent.create!(
        merchant: @merchant,
        customer: @customer,
        payment_method: @payment_method,
        amount_cents: amount_cents,
        currency: 'USD',
        status: status
      )
    end

    def create_captured_intent!
      pi = create_intent!(status: 'authorized')
      Transaction.create!(payment_intent: pi, kind: 'authorize', status: 'succeeded', amount_cents: pi.amount_cents)
      CaptureService.call(payment_intent: pi.reload)
      pi.reload
    end

    # Extra rows for list / index perf (merchant-scoped).
    def seed_for_list_endpoints!(extra_intents: 24, authorized_sample: 8)
      extra_intents.times { create_intent!(status: 'created') }
      authorized_sample.times do
        pi = create_intent!(status: 'created')
        AuthorizeService.call(payment_intent: pi)
      end
    end
  end
end
