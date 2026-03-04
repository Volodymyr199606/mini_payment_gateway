# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentResult do
  describe 'defaults' do
    it 'builds with default metadata when metadata is nil' do
      result = described_class.new(reply_text: 'Hi', agent_key: 'support_faq')
      expect(result.reply_text).to eq('Hi')
      expect(result.agent_key).to eq('support_faq')
      expect(result.metadata).to include(
        retriever: nil,
        docs_used_count: 0,
        summary_used: false,
        guardrail_reask: false
      )
    end

    it 'merges custom metadata over defaults' do
      result = described_class.new(
        reply_text: 'Ok',
        citations: [{ file: 'a.md', heading: 'A' }],
        agent_key: 'operational',
        metadata: { docs_used_count: 3, guardrail_reask: true }
      )
      expect(result.metadata[:docs_used_count]).to eq(3)
      expect(result.metadata[:guardrail_reask]).to eq(true)
      expect(result.metadata[:summary_used]).to eq(false)
      expect(result.citations.size).to eq(1)
    end
  end
end
