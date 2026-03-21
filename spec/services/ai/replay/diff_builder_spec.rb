# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Replay::DiffBuilder do
  describe '.call' do
    it 'returns empty differences when summaries match' do
      summary = {
        agent_key: 'tool:get_payment_intent',
        composition_mode: 'tool_only',
        tool_used: true,
        tool_names: ['get_payment_intent'],
        success: true
      }
      diff = described_class.call(original_summary: summary, replay_summary: summary)
      expect(diff).to eq([])
    end

    it 'returns differences when agent_key differs' do
      orig = { agent_key: 'tool:get_payment_intent', composition_mode: 'tool_only' }
      repl = { agent_key: 'operational', composition_mode: 'docs_only' }
      diff = described_class.call(original_summary: orig, replay_summary: repl)
      expect(diff.map { |d| d[:field] }).to include('agent_key', 'composition_mode')
      expect(diff.any? { |d| d[:field] == 'agent_key' && d[:original] == 'tool:get_payment_intent' && d[:replayed] == 'operational' }).to be true
    end

    it 'compares tool_names as sets' do
      orig = { tool_names: %w[get_transaction get_payment_intent] }
      repl = { tool_names: %w[get_payment_intent get_transaction] }
      diff = described_class.call(original_summary: orig, replay_summary: repl)
      expect(diff.any? { |d| d[:field] == 'tool_names' }).to be false
    end
  end

  describe '.matched_flags' do
    it 'sets matched_path true when composition_mode and execution_mode match' do
      orig = { composition_mode: 'tool_only', execution_mode: 'deterministic_only' }
      repl = { composition_mode: 'tool_only', execution_mode: 'deterministic_only' }
      flags = described_class.matched_flags(original_summary: orig, replay_summary: repl)
      expect(flags[:matched_path]).to be true
      expect(flags[:matched_composition_mode]).to be true
    end

    it 'sets matched_tool_usage true when tool_names and tool_used match' do
      orig = { tool_used: true, tool_names: ['get_payment_intent'] }
      repl = { tool_used: true, tool_names: ['get_payment_intent'] }
      flags = described_class.matched_flags(original_summary: orig, replay_summary: repl)
      expect(flags[:matched_tool_usage]).to be true
    end

    it 'sets matched_policy_decisions when authorization flags match' do
      orig = { authorization_denied: false, tool_blocked_by_policy: false }
      repl = { authorization_denied: false, tool_blocked_by_policy: false }
      flags = described_class.matched_flags(original_summary: orig, replay_summary: repl)
      expect(flags[:matched_policy_decisions]).to be true
    end

    it 'sets matched_skill_usage when skill_keys match' do
      orig = { skill_keys: %w[payment_state_explainer] }
      repl = { skill_keys: %w[payment_state_explainer] }
      flags = described_class.matched_flags(original_summary: orig, replay_summary: repl)
      expect(flags[:matched_skill_usage]).to be true
    end

    it 'sets matched_skill_usage false when skill_keys differ' do
      orig = { skill_keys: %w[payment_state_explainer] }
      repl = { skill_keys: [] }
      flags = described_class.matched_flags(original_summary: orig, replay_summary: repl)
      expect(flags[:matched_skill_usage]).to be false
    end
  end

  describe 'skill_keys in diff' do
    it 'reports difference when skill_keys differ' do
      orig = { skill_keys: %w[payment_state_explainer] }
      repl = { skill_keys: %w[followup_rewriter] }
      diff = described_class.call(original_summary: orig, replay_summary: repl)
      expect(diff.any? { |d| d[:field] == 'skill_keys' }).to be true
    end
  end
end
