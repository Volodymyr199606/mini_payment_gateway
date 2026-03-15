# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Orchestration::ConstrainedRunner do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
    allow(Ai::Observability::EventLogger).to receive(:log_orchestration_run)
  end

  describe '.call' do
    it 'returns no_orchestration when message is blank' do
      result = described_class.call(message: '  ', merchant_id: merchant.id)
      expect(result.orchestration_used?).to be false
      expect(result.step_count).to eq(0)
    end

    it 'returns no_orchestration when merchant_id is blank' do
      result = described_class.call(message: 'transaction id 1', merchant_id: nil)
      expect(result.orchestration_used?).to be false
    end

    it 'returns no_orchestration when no intent detected (ambiguous request)' do
      result = described_class.call(
        message: 'What is the refund policy?',
        merchant_id: merchant.id
      )
      expect(result.orchestration_used?).to be false
    end

    it 'runs single step for get_merchant_account and does not run second step' do
      result = described_class.call(
        message: 'Show my account info',
        merchant_id: merchant.id
      )
      expect(result.orchestration_used?).to be true
      expect(result.step_count).to eq(1)
      expect(result.tool_names).to eq(['get_merchant_account'])
      expect(result.success?).to be true
      expect(result.reply_text).to include(merchant.name)
      expect(result.deterministic_data).to be_present
      expect(result.steps.first[:tool_name]).to eq('get_merchant_account')
    end

    it 'sets explanation_metadata when deterministic template applies (e.g. get_payment_intent)' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD',
        status: 'authorized'
      )
      result = described_class.call(
        message: "payment intent id #{pi.id}",
        merchant_id: merchant.id
      )
      expect(result.orchestration_used?).to be true
      expect(result.success?).to be true
      expect(result.explanation_metadata).to be_a(Hash)
      expect(result.explanation_metadata[:deterministic_explanation_used]).to be true
      expect(result.explanation_metadata[:explanation_type]).to eq('payment_intent')
      expect(result.explanation_metadata[:explanation_key]).to eq('authorized')
      expect(result.explanation_metadata[:llm_skipped_due_to_template]).to be true
      expect(result.reply_text).to include('authorized')
      expect(result.reply_text).to include(pi.id.to_s)
    end

    it 'runs single step for get_payment_intent (no follow-up rule)' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      result = described_class.call(
        message: "payment intent id #{pi.id}",
        merchant_id: merchant.id
      )
      expect(result.orchestration_used?).to be true
      expect(result.step_count).to eq(1)
      expect(result.tool_names).to eq(['get_payment_intent'])
      expect(result.success?).to be true
      expect(result.reply_text).to include(pi.id.to_s)
    end

    it 'runs two steps for transaction then payment intent when transaction has payment_intent_id' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      txn = pi.transactions.create!(kind: 'capture', status: 'succeeded', amount_cents: 1000, processor_ref: 'txn_abc123')
      # Ensure get_transaction returns data with payment_intent_id (required for step 2)
      step1 = ::Ai::Tools::Executor.call(
        tool_name: 'get_transaction',
        args: { transaction_id: txn.id },
        context: { merchant_id: merchant.id, request_id: 'test' }
      )
      expect(step1[:success]).to be(true), "get_transaction failed: #{step1[:error].inspect}"
      expect(step1[:data][:payment_intent_id]).to eq(pi.id), "step1 data missing payment_intent_id: #{step1[:data]&.keys}"

      result = described_class.call(
        message: "transaction id #{txn.id}",
        merchant_id: merchant.id
      )
      expect(result.orchestration_used?).to be true
      expect(result.step_count).to eq(2)
      expect(result.tool_names).to eq(%w[get_transaction get_payment_intent])
      expect(result.success?).to be true
      expect(result.deterministic_data).to be_a(Hash)
      expect(result.deterministic_data[:transaction]).to be_present
      expect(result.deterministic_data[:payment_intent]).to be_present
      expect(result.reply_text).to include('Transaction')
      expect(result.reply_text).to include('Payment Intent')
      expect(Ai::Observability::EventLogger).to have_received(:log_orchestration_run).with(
        hash_including(
          step_count: 2,
          tool_names: %w[get_transaction get_payment_intent],
          success: true
        )
      )
    end

    it 'enforces max 2 steps (no third step)' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      txn = pi.transactions.create!(kind: 'capture', status: 'succeeded', amount_cents: 1000, processor_ref: 'txn_xyz')
      result = described_class.call(
        message: "transaction id #{txn.id}",
        merchant_id: merchant.id
      )
      expect(result.step_count).to eq(2)
      expect(result.steps.size).to eq(2)
    end

    it 'runs only step 1 when get_transaction succeeds but has no payment_intent_id (edge case)' do
      # Transaction model belongs_to payment_intent, so it always has payment_intent_id when created via pi.transactions.
      # To test "no follow-up id" we'd need a transaction without pi_id - not possible with current schema.
      # So we test: when step 1 is get_ledger_summary there is no follow-up rule
      result = described_class.call(
        message: 'last 7 days totals',
        merchant_id: merchant.id
      )
      expect(result.orchestration_used?).to be true
      expect(result.step_count).to eq(1)
      expect(result.tool_names).to eq(['get_ledger_summary'])
    end

    it 'passes deterministic_data to result (tool output is source of truth)' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 2500,
        currency: 'USD'
      )
      txn = pi.transactions.create!(kind: 'capture', status: 'succeeded', amount_cents: 2500, processor_ref: 'txn_ref')
      result = described_class.call(
        message: "transaction id #{txn.id}",
        merchant_id: merchant.id
      )
      expect(result.step_count).to eq(2), "expected 2 steps (transaction then payment_intent), got #{result.step_count}"
      expect(result.deterministic_data[:transaction]).to be_present
      expect(result.deterministic_data[:payment_intent]).to be_present
      expect(result.deterministic_data[:transaction][:amount_cents]).to eq(2500)
      expect(result.deterministic_data[:payment_intent][:amount_cents]).to eq(2500)
    end
  end
end
