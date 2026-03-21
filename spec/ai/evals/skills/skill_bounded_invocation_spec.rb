# frozen_string_literal: true

require 'rails_helper'

# Verifies bounded skill invocation: no unbounded calls, metadata present.
RSpec.describe 'AI skill bounded invocation', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  it 'MAX_INVOCATIONS_PER_REQUEST is 2' do
    expect(Ai::Skills::InvocationPlanner::MAX_INVOCATIONS_PER_REQUEST).to eq(2)
  end

  it 'invocation result includes required audit metadata' do
    pi = merchant.payment_intents.create!(
      customer: merchant.customers.create!(email: "c_#{SecureRandom.hex(4)}@x.com"),
      amount_cents: 1000,
      currency: 'USD',
      status: 'captured'
    )
    run_result = Ai::Orchestration::RunResult.new(
      orchestration_used: true,
      step_count: 1,
      tool_names: ['get_payment_intent'],
      deterministic_data: { id: pi.id, status: 'captured', amount_cents: 1000, currency: 'USD' },
      success: true,
      reply_text: 'Raw'
    )
    outcome = Ai::Skills::InvocationCoordinator.post_tool(
      agent_key: :operational,
      merchant_id: merchant.id,
      message: 'status',
      tool_names: ['get_payment_intent'],
      deterministic_data: run_result.deterministic_data,
      run_result: run_result
    )

    expect(outcome[:invocation_results].size).to be <= 2
    outcome[:invocation_results].each do |r|
      expect(r).to have_key(:skill_key)
      expect(r).to have_key(:phase)
      expect(r).to have_key(:invoked)
      expect(r).to have_key(:reason_code) if r[:invoked]
    end
  end

  it 'plan_all_for_request returns at most MAX_INVOCATIONS' do
    ctx = Ai::Skills::InvocationContext.for_post_tool(
      agent_key: :operational,
      merchant_id: merchant.id,
      message: 'status',
      tool_names: ['get_payment_intent'],
      deterministic_data: { payment_intent: { id: 1 } },
      run_result: nil
    )
    planned = Ai::Skills::InvocationPlanner.plan_all_for_request(context: ctx, phase: :post_tool)
    expect(planned.size).to be <= Ai::Skills::InvocationPlanner::MAX_INVOCATIONS_PER_REQUEST
  end
end
