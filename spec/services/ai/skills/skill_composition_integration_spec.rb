# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Skill composition integration' do
  describe Ai::Skills::ConflictResolver do
    it 'prefers deterministic primary over generic LLM-style primary' do
      candidates = [
        { skill_key: :payment_state_explainer, slot: :primary_explanation, text: 'PI captured.', deterministic: true },
        { skill_key: :report_explainer, slot: :primary_explanation, text: 'Here is a nice story.', deterministic: false }
      ]
      out = described_class.resolve(candidates: candidates, tool_reply: '')
      expect(out[:contributing]).to include(:payment_state_explainer)
      expect(out[:suppressed]).to include(:report_explainer)
      expect(out[:deterministic_primary]).to be true
      reason = out[:suppressed_reasons].find { |r| r['skill_key'] == 'report_explainer' }
      expect(reason['reason_code']).to eq('deterministic_over_generic')
    end

    it 'uses canonical order when multiple deterministic skills target primary' do
      candidates = [
        { skill_key: :ledger_period_summary, slot: :primary_explanation, text: 'Ledger A', deterministic: true },
        { skill_key: :payment_state_explainer, slot: :primary_explanation, text: 'PI B', deterministic: true }
      ]
      out = described_class.resolve(candidates: candidates, tool_reply: '')
      expect(out[:contributing]).to include(:payment_state_explainer)
      expect(out[:suppressed]).to include(:ledger_period_summary)
      expect(out[:rules_applied]).to include('canonical_primary_precedence')
    end

    it 'keeps discrepancy in supporting_analysis without changing primary totals' do
      candidates = [
        { skill_key: :ledger_period_summary, slot: :primary_explanation, text: 'Net $10', deterministic: true },
        { skill_key: :discrepancy_detector, slot: :supporting_analysis, text: 'Check: anomaly', deterministic: true }
      ]
      out = described_class.resolve(candidates: candidates, tool_reply: '')
      expect(out[:primary_text]).to include('Net $10')
      expect(out[:primary_text]).to include('anomaly')
      expect(out[:rules_applied]).to include('additive_slots_append_only')
    end

    it 'applies style_transform as final visible text without dropping deterministic primary body when no style' do
      candidates = [
        { skill_key: :payment_state_explainer, slot: :primary_explanation, text: 'Facts.', deterministic: true },
        { skill_key: :followup_rewriter, slot: :style_transform, text: '• Facts.', deterministic: false }
      ]
      out = described_class.resolve(candidates: candidates, tool_reply: '')
      expect(out[:primary_text]).to include('• Facts.')
      expect(out[:style_transform_applied]).to be true
    end
  end

  describe Ai::Skills::CompositionPlanner do
    it 'passes deterministic_primary and suppressed_reasons through from multi-skill resolve' do
      results = [
        { skill_key: 'payment_state_explainer', invoked: true, success: true, deterministic: true, explanation: 'A' },
        { skill_key: 'report_explainer', invoked: true, success: true, deterministic: false, explanation: 'B' }
      ]
      r = described_class.plan(reply_text: '', invocation_results: results, agent_key: :operational)
      expect(r.deterministic_primary).to be true
      expect(r.suppressed_reason_codes).to be_a(Array)
    end
  end
end
