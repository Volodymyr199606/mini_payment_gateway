# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::ConflictResolver do
  describe '.resolve' do
    it 'prefers deterministic over non-deterministic for same primary slot' do
      candidates = [
        { skill_key: :payment_state_explainer, slot: :primary_explanation, text: 'Det', deterministic: true },
        { skill_key: :report_explainer, slot: :primary_explanation, text: 'LLM fluff', deterministic: false }
      ]
      out = described_class.resolve(candidates: candidates, tool_reply: 'x')
      expect(out[:contributing]).to include(:payment_state_explainer)
      expect(out[:suppressed]).to include(:report_explainer)
      expect(out[:rules_applied]).to include('deterministic_skill_over_generic')
    end
  end
end
