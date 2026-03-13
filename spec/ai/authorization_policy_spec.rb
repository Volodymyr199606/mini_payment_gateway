# frozen_string_literal: true

require 'rails_helper'

# Integration specs for centralized AI authorization layer.
# Verifies cross-merchant blocking, safe error responses, and adversarial prompts.
RSpec.describe 'AI Authorization Policy Integration' do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:other_merchant) { create_merchant_with_api_key(name: 'Other').first }

  before do
    allow(Ai::Observability::EventLogger).to receive(:log_tool_call)
  end

  describe 'deterministic tools' do
    describe 'get_payment_intent cross-merchant' do
      it 'blocks access when requesting another merchant payment intent' do
        pi = merchant.payment_intents.create!(
          customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
          amount_cents: 1000,
          currency: 'USD'
        )
        result = Ai::Tools::Executor.call(
          tool_name: 'get_payment_intent',
          args: { payment_intent_id: pi.id },
          context: { merchant_id: other_merchant.id }
        )
        expect(result[:success]).to be false
        expect(result[:error_code]).to eq('access_denied')
        expect(result[:authorization_denied]).to be true
        expect(result[:error]).to eq(Ai::Policy::Authorization.denied_message)
      end

      it 'does not leak existence of another merchants record' do
        pi = merchant.payment_intents.create!(
          customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
          amount_cents: 1000,
          currency: 'USD'
        )
        result = Ai::Tools::Executor.call(
          tool_name: 'get_payment_intent',
          args: { payment_intent_id: pi.id },
          context: { merchant_id: other_merchant.id }
        )
        expect(result[:error]).not_to include('not found')
        expect(result[:error]).not_to include('exist')
        expect(result[:error]).not_to include('merchant')
      end
    end

    describe 'get_transaction cross-merchant' do
      it 'blocks access when requesting another merchant transaction' do
        pi = merchant.payment_intents.create!(
          customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
          amount_cents: 1000,
          currency: 'USD'
        )
        tx = Transaction.create!(
          payment_intent: pi,
          processor_ref: "tx_#{SecureRandom.hex(12)}",
          amount_cents: 1000,
          kind: 'authorize',
          status: 'succeeded'
        )
        result = Ai::Tools::Executor.call(
          tool_name: 'get_transaction',
          args: { transaction_id: tx.id },
          context: { merchant_id: other_merchant.id }
        )
        expect(result[:success]).to be false
        expect(result[:error_code]).to eq('access_denied')
        expect(result[:error]).to eq(Ai::Policy::Authorization.denied_message)
      end
    end

    describe 'get_webhook_event cross-merchant' do
      it 'blocks access when requesting another merchant webhook event' do
        we = WebhookEvent.create!(merchant: merchant, event_type: 'payment_intent.succeeded', payload: { id: 'ev_1' })
        result = Ai::Tools::Executor.call(
          tool_name: 'get_webhook_event',
          args: { webhook_event_id: we.id },
          context: { merchant_id: other_merchant.id }
        )
        expect(result[:success]).to be false
        expect(result[:error_code]).to eq('access_denied')
      end
    end

    describe 'get_merchant_account' do
      it 'returns only current merchant for get_merchant_account' do
        result = Ai::Tools::Executor.call(
          tool_name: 'get_merchant_account',
          args: {},
          context: { merchant_id: merchant.id }
        )
        expect(result[:success]).to be true
        expect(result[:data][:id]).to eq(merchant.id)
        expect(result[:data][:name]).to eq(merchant.name)
      end

      it 'does not return other merchant data' do
        result = Ai::Tools::Executor.call(
          tool_name: 'get_merchant_account',
          args: {},
          context: { merchant_id: merchant.id }
        )
        expect(result[:data][:id]).not_to eq(other_merchant.id)
      end
    end

    describe 'get_ledger_summary' do
      it 'is merchant-scoped via context' do
        result = Ai::Tools::Executor.call(
          tool_name: 'get_ledger_summary',
          args: { from: '2025-01-01', to: '2025-01-31' },
          context: { merchant_id: merchant.id }
        )
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(Hash)
      end

      it 'denies when merchant_id missing' do
        result = Ai::Tools::Executor.call(
          tool_name: 'get_ledger_summary',
          args: { from: '2025-01-01', to: '2025-01-31' },
          context: {}
        )
        expect(result[:success]).to be false
        expect(result[:authorization_denied]).to be true
      end
    end
  end

  describe 'follow-up inheritance' do
    it 'blocks inherited payment_intent when ownership does not match' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      recent = [
        { role: 'user', content: "Status of payment intent #{pi.id}?" },
        { role: 'assistant', content: 'Authorized.' },
        { role: 'user', content: 'Was it captured?' }
      ]
      result = Ai::Followups::IntentResolver.call(
        message: 'Was it captured?',
        recent_messages: recent,
        merchant_id: other_merchant.id
      )
      expect(result[:intent]).to be_nil
      expect(result[:followup][:followup_inheritance_blocked]).to be true
    end

    it 'allows inherited payment_intent when ownership matches' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      recent = [
        { role: 'user', content: "Status of payment intent #{pi.id}?" },
        { role: 'assistant', content: 'Authorized.' },
        { role: 'user', content: 'Was it captured?' }
      ]
      result = Ai::Followups::IntentResolver.call(
        message: 'Was it captured?',
        recent_messages: recent,
        merchant_id: merchant.id
      )
      expect(result[:intent]).to be_present
      expect(result[:intent][:tool_name]).to eq('get_payment_intent')
      expect(result[:intent][:args][:payment_intent_id]).to eq(pi.id)
    end
  end

  describe 'constrained orchestration' do
    it 'halts on authorization failure and does not run step 2' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      # Simulate request for another merchant's transaction: intent detector may return get_transaction
      # We force intent with foreign pi's transaction - the tool will deny
      tx = Transaction.create!(
        payment_intent: pi,
        processor_ref: "tx_#{SecureRandom.hex(12)}",
        amount_cents: 1000,
        kind: 'authorize',
        status: 'succeeded'
      )
      resolved_intent = { tool_name: 'get_transaction', args: { transaction_id: tx.id } }
      run_result = Ai::Orchestration::ConstrainedRunner.call(
        message: "Show me transaction #{tx.id}",
        merchant_id: other_merchant.id,
        request_id: 'test-req',
        resolved_intent: resolved_intent
      )
      expect(run_result.orchestration_used?).to be true
      expect(run_result.success?).to be false
      expect(run_result.metadata[:authorization_denied]).to be true
      expect(run_result.halted_reason).to eq('authorization_denied')
    end

    it 'does not expose record existence in orchestration failure' do
      pi = merchant.payment_intents.create!(
        customer_id: merchant.customers.create!(email: 'c@x.com', merchant_id: merchant.id).id,
        amount_cents: 1000,
        currency: 'USD'
      )
      resolved_intent = { tool_name: 'get_payment_intent', args: { payment_intent_id: pi.id } }
      run_result = Ai::Orchestration::ConstrainedRunner.call(
        message: "Show me payment intent #{pi.id}",
        merchant_id: other_merchant.id,
        request_id: 'test-req',
        resolved_intent: resolved_intent
      )
      expect(run_result.reply_text).not_to include('not found')
      expect(run_result.reply_text).not_to include('exist')
    end
  end
end
