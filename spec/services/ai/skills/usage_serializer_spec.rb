# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::UsageSerializer do
  describe '.normalize' do
    it 'normalizes a single InvocationResult hash to safe shape' do
      raw = { skill_key: 'payment_state_explainer', phase: 'post_tool', invoked: true, success: true, reason_code: 'matched' }
      result = described_class.normalize(raw: raw, agent_key: 'operational', affected_final_response: true)
      expect(result.size).to eq(1)
      expect(result.first['skill_key']).to eq('payment_state_explainer')
      expect(result.first['phase']).to eq('post_tool')
      expect(result.first['invoked']).to be(true)
      expect(result.first['success']).to be(true)
      expect(result.first['reason_code']).to eq('matched')
      expect(result.first['affected_final_response']).to be(true)
      expect(result.first.keys - described_class::SAFE_KEYS).to be_empty
    end

    it 'strips unsafe fields' do
      raw = { skill_key: 'x', phase: 'post_tool', invoked: true, raw_payload: 'secret', internal_prompt: 'foo' }
      result = described_class.normalize(raw: raw)
      expect(result.first).not_to have_key('raw_payload')
      expect(result.first).not_to have_key('internal_prompt')
      expect(result.first['skill_key']).to eq('x')
    end

    it 'returns empty array for blank input' do
      expect(described_class.normalize(raw: nil)).to eq([])
      expect(described_class.normalize(raw: [])).to eq([])
    end

    it 'handles InvocationResult objects' do
      inv = Ai::Skills::InvocationResult.executed(
        skill_key: 'followup_rewriter',
        phase: 'pre_composition',
        reason_code: 'concise_rewrite',
        skill_result: double(success: true, deterministic: true)
      )
      result = described_class.normalize(raw: inv, agent_key: 'support_faq')
      expect(result.size).to eq(1)
      expect(result.first['skill_key']).to eq('followup_rewriter')
      expect(result.first['phase']).to eq('pre_composition')
      expect(result.first['invoked']).to be(true)
    end

    it 'sets affected_final_response from parameter when not in raw' do
      raw = { skill_key: 'x', phase: 'p', invoked: true }
      result = described_class.normalize(raw: raw, affected_final_response: true)
      expect(result.first['affected_final_response']).to be(true)
    end

    it 'omits entries without skill_key' do
      raw = [{ phase: 'p', invoked: false }, { skill_key: 'valid', phase: 'p', invoked: true }]
      result = described_class.normalize(raw: raw)
      expect(result.size).to eq(1)
      expect(result.first['skill_key']).to eq('valid')
    end
  end

  describe '.summary' do
    it 'returns zeros for empty list' do
      s = described_class.summary([])
      expect(s[:skill_count]).to eq(0)
      expect(s[:skill_keys]).to eq([])
      expect(s[:skill_failures]).to eq(0)
    end

    it 'counts invoked, failed, and affected' do
      list = [
        { 'skill_key' => 'a', 'invoked' => true, 'success' => true, 'affected_final_response' => true },
        { 'skill_key' => 'b', 'invoked' => true, 'success' => false, 'affected_final_response' => false }
      ]
      s = described_class.summary(list)
      expect(s[:skill_count]).to eq(2)
      expect(s[:skill_keys]).to contain_exactly('a', 'b')
      expect(s[:skill_failures]).to eq(1)
      expect(s[:affected_response_count]).to eq(1)
    end
  end
end
