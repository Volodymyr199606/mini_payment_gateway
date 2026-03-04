# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI golden eval harness', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }

  before do
    Ai::Rag::DocsIndex.reset!
    Ai::Rag::ContextGraph.reset!
    stub_groq = instance_double(
      Ai::GroqClient,
      chat: { content: Ai::Evals::Runner::STUB_REPLY, model_used: 'eval', fallback_used: false }
    )
    allow(Ai::GroqClient).to receive(:new).and_return(stub_groq)
    ledger_stub = {
      currency: 'USD',
      from: '2025-01-01T00:00:00Z',
      to: '2025-01-08T23:59:59Z',
      totals: { charges_cents: 100_00, refunds_cents: 20_00, fees_cents: 5_00, net_cents: 75_00 },
      counts: { captures_count: 10, refunds_count: 2 }
    }
    allow(Reporting::LedgerSummary).to receive(:new).and_return(
      instance_double(Reporting::LedgerSummary, call: ledger_stub)
    )
  end

  Ai::Evals::Runner.load_questions.each do |agent_key, questions|
    Array(questions).each do |question|
      it "#{agent_key}: #{question.to_s.strip[0..70]}#{'...' if question.to_s.length > 70}" do
        run = Ai::Evals::Runner.run_one(
          question.to_s.strip,
          merchant_id: merchant.id,
          expected_agent_key: agent_key,
          stub_llm: true
        )
        expect(run[:errors]).to eq([]), "Eval failures: #{run[:errors].join('; ')}"
      end
    end
  end
end
