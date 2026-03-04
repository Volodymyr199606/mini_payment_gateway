# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::ReportingCalculationAgent do
  include ApiHelpers

  let(:merchant) { create_merchant_with_api_key.first }
  let(:stub_summary) do
    {
      currency: 'USD',
      from: '2025-01-01T00:00:00Z',
      to: '2025-02-11T23:59:59Z',
      totals: { charges_cents: 100_00, refunds_cents: 20_00, fees_cents: 5_00, net_cents: 75_00 },
      counts: { captures_count: 10, refunds_count: 2 }
    }
  end

  describe '#call' do
    it 'when no range specified, reply includes ALL TIME wording and inferred note' do
      allow(Reporting::LedgerSummary).to receive(:new).and_return(
        instance_double(Reporting::LedgerSummary, call: stub_summary)
      )

      agent = described_class.new(merchant_id: merchant.id, message: 'how much refunded?')
      result = agent.call

      expect(result.reply_text).to include('ALL TIME')
      expect(result.reply_text).to include("You didn't specify a range, so I used ALL TIME")
      expect(result.reply_text).to include("Ask 'last 30 days' if you want a narrower window")
    end

    it 'totals come from LedgerSummary (stub results appear in reply)' do
      allow(Reporting::LedgerSummary).to receive(:new).and_return(
        instance_double(Reporting::LedgerSummary, call: stub_summary)
      )

      agent = described_class.new(merchant_id: merchant.id, message: 'how much last 7 days?')
      result = agent.call

      expect(result.reply_text).to include('$100.00')
      expect(result.reply_text).to include('$20.00')
      expect(result.reply_text).to include('$5.00')
      expect(result.reply_text).to include('$75.00')
      expect(result.data).to eq(stub_summary)
    end

    it 'returns AgentResult with deterministic fields set' do
      allow(Reporting::LedgerSummary).to receive(:new).and_return(
        instance_double(Reporting::LedgerSummary, call: stub_summary)
      )

      agent = described_class.new(merchant_id: merchant.id, message: 'totals', context_text: nil, citations: [])
      result = agent.call

      expect(result).to be_a(Ai::AgentResult)
      expect(result.agent_key).to eq('reporting_calculation')
      expect(result.model_used).to be_nil
      expect(result.fallback_used).to eq(false)
      expect(result.citations).to eq([])
      expect(result.metadata).to include(docs_used_count: 0, summary_used: false, guardrail_reask: false)
      expect(result.data).to eq(stub_summary)
    end
  end
end
