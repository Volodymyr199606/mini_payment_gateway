# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Orchestration::RunResult do
  describe '.no_orchestration' do
    it 'returns result with orchestration_used false and step_count 0' do
      result = described_class.no_orchestration
      expect(result.orchestration_used?).to be false
      expect(result.orchestration_used).to be false
      expect(result.step_count).to eq(0)
      expect(result.steps).to eq([])
      expect(result.tool_names).to eq([])
      expect(result.success?).to be false
      expect(result.halted_reason).to be_nil
      expect(result.deterministic_data).to be_nil
      expect(result.reply_text).to eq('')
    end
  end

  describe 'with steps' do
    it 'exposes step_summaries_for_debug without secrets' do
      steps = [
        { tool_name: 'get_transaction', success: true, result_summary: 'found', latency_ms: 10 },
        { tool_name: 'get_payment_intent', success: true, result_summary: 'found', latency_ms: 5 }
      ]
      result = described_class.new(
        orchestration_used: true,
        step_count: 2,
        steps: steps,
        tool_names: %w[get_transaction get_payment_intent],
        success: true,
        deterministic_data: { transaction: {}, payment_intent: {} },
        metadata: { latency_ms: 15 },
        reply_text: 'Transaction #1...'
      )
      expect(result.orchestration_used?).to be true
      expect(result.step_count).to eq(2)
      expect(result.tool_names).to eq(%w[get_transaction get_payment_intent])
      expect(result.success?).to be true
      summaries = result.step_summaries_for_debug
      expect(summaries.size).to eq(2)
      expect(summaries.first).to eq({ tool_name: 'get_transaction', success: true, result_summary: 'found', latency_ms: 10 })
      expect(summaries.last).to eq({ tool_name: 'get_payment_intent', success: true, result_summary: 'found', latency_ms: 5 })
    end
  end
end
