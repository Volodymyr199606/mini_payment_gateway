# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ReplayResult contract' do
  describe 'to_h shape' do
    it 'includes replay_possible and matched_* fields for UI and comparison' do
      result = Ai::Replay::ReplayResult.new(
        replay_possible: true,
        original_audit_id: 1,
        original_summary: { composition_mode: 'tool_only', tool_used: true },
        replay_summary: { composition_mode: 'tool_only', tool_used: true },
        differences: [],
        matched_path: true,
        matched_policy_decisions: true,
        matched_tool_usage: true,
        matched_composition_mode: true,
        matched_debug_metadata: true,
        reason_codes: ['intent_replay']
      )
      h = result.to_h
      expect(h).to have_key(:replay_possible)
      expect(h[:replay_possible]).to be_in([true, false])
      expect(h).to have_key(:matched_path)
      expect(h).to have_key(:matched_policy_decisions)
      expect(h).to have_key(:matched_tool_usage)
      expect(h).to have_key(:matched_composition_mode)
      expect(h).to have_key(:matched_debug_metadata)
      expect(h).to have_key(:differences)
      expect(h[:differences]).to be_a(Array)
      expect(h).to have_key(:original_summary)
      expect(h).to have_key(:replay_summary)
    end

    it 'differences items have field, original, replayed when present' do
      result = Ai::Replay::ReplayResult.new(
        replay_possible: true,
        differences: [
          { field: 'composition_mode', original: 'tool_only', replayed: 'docs_only' }
        ],
        original_summary: {},
        replay_summary: {}
      )
      h = result.to_h
      expect(h[:differences].first).to have_key(:field)
      expect(h[:differences].first).to have_key(:original)
      expect(h[:differences].first).to have_key(:replayed)
    end

    it 'does not expose sensitive fields' do
      result = Ai::Replay::ReplayResult.new(
        replay_possible: true,
        original_summary: { tool_used: true },
        replay_summary: { tool_used: true },
        differences: []
      )
      AiContractHelpers.assert_no_forbidden_keys!(result.to_h, contract_name: 'ReplayResult')
    end
  end
end
