# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dashboard Payment Intents', type: :request do
  include ApiHelpers

  def csrf_token
    get dashboard_sign_in_path
    response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def sign_in_merchant(merchant, api_key)
    post dashboard_sign_in_path, params: { api_key: api_key, authenticity_token: csrf_token }
    follow_redirect! if response.redirect?
  end

  def create_payment_intent_via_dashboard(amount_cents: 1000)
    get new_dashboard_payment_intent_path
    expect(response).to have_http_status(:ok) # must be signed in
    token = response.body[/name="csrf-token" content="([^"]+)"/, 1] ||
            response.body[/name="authenticity_token" value="([^"]+)"/, 1]
    post dashboard_payment_intents_path, params: {
      authenticity_token: token,
      payment_intent: { amount_cents: amount_cents, currency: "usd" }
    }
  end

  describe 'POST /dashboard/payment_intents (create)' do
    it 'uses current_merchant.email for default customer when present' do
      merchant, api_key = create_merchant_with_api_key
      sign_in_merchant(merchant, api_key)
      get dashboard_root_path
      expect(response).to have_http_status(:ok), "Should be signed in"

      create_payment_intent_via_dashboard(amount_cents: 2000)

      error_html = response.body[/dashboard-alert-error[^>]*>([^<]+)/m, 1]
      expect(response).to have_http_status(:found), "Expected redirect, got #{response.status}#{error_html.present? ? ": #{error_html.strip}" : ''}"
      pi = PaymentIntent.last
      expect(pi).to be_present, "No PaymentIntent created"
      expect(response).to redirect_to(dashboard_payment_intent_path(pi))
      expect(pi.customer.email).to eq(merchant.email.downcase)
      expect(pi.customer.merchant_id).to eq(merchant.id)
    end

    it 'reuses existing customer when same email exists for merchant' do
      merchant, api_key = create_merchant_with_api_key
      sign_in_merchant(merchant, api_key)

      create_payment_intent_via_dashboard(amount_cents: 1000)
      expect(response).to redirect_to(dashboard_payment_intent_path(PaymentIntent.last))
      first_customer_id = PaymentIntent.last.customer_id

      create_payment_intent_via_dashboard(amount_cents: 2000)
      expect(response).to redirect_to(dashboard_payment_intent_path(PaymentIntent.last))
      second_customer_id = PaymentIntent.last.customer_id

      expect(first_customer_id).to eq(second_customer_id)
      expect(merchant.customers.count).to eq(1)
    end

  end
end
