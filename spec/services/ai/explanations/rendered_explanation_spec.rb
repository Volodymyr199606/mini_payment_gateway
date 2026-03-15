# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Explanations::RenderedExplanation do
  describe '.for_tool' do
    it 'builds a RenderedExplanation with deterministic true' do
      out = described_class.for_tool(
        explanation_text: 'Payment intent 1 is authorized.',
        explanation_type: 'payment_intent',
        explanation_key: 'authorized',
        metadata: { tool_name: 'get_payment_intent' }
      )
      expect(out.explanation_text).to eq('Payment intent 1 is authorized.')
      expect(out.explanation_type).to eq('payment_intent')
      expect(out.explanation_key).to eq('authorized')
      expect(out.deterministic).to be true
      expect(out.metadata[:tool_name]).to eq('get_payment_intent')
    end
  end

  describe '#to_audit_metadata' do
    it 'returns safe audit keys including llm_skipped_due_to_template' do
      out = described_class.for_tool(
        explanation_text: 'Ok',
        explanation_type: 'transaction',
        explanation_key: 'capture_succeeded'
      )
      meta = out.to_audit_metadata
      expect(meta[:deterministic_explanation_used]).to be true
      expect(meta[:explanation_type]).to eq('transaction')
      expect(meta[:explanation_key]).to eq('capture_succeeded')
      expect(meta[:llm_skipped_due_to_template]).to be true
    end
  end
end
