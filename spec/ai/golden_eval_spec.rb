# frozen_string_literal: true

require 'rails_helper'

# Integration spec: run full golden eval harness with stubbed LLM and LedgerSummary.
# Uses spec/fixtures/ai/golden_questions.yml and expects all cases to pass.
RSpec.describe 'AI golden eval harness', type: :eval do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:fixture_path) { Rails.root.join('spec/fixtures/ai/golden_questions.yml') }

  before do
    Ai::Rag::DocsIndex.reset!
    Ai::Rag::ContextGraph.reset!
    stub_groq = instance_double(
      Ai::GroqClient,
      chat: { content: 'Stub reply for eval. No external API.', model_used: 'eval', fallback_used: false }
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

  it 'runs all golden questions and every case passes' do
    skip 'fixture missing' unless fixture_path.exist?
    results = Ai::Evals::Runner.run_all(merchant_id: merchant.id, path: fixture_path)
    failed = results.reject { |r| r[:passed_overall] }
    expect(failed).to eq([]), lambda {
      reasons = failed.map { |r| "[#{r[:id]}] #{r.dig(:metadata, :failure_reasons)&.join(', ')}: #{r[:question][0, 50]}..." }.join("\n")
      "Eval failures:\n#{reasons}"
    }
  end
end
