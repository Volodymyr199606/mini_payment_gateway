# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Performance::CacheKeys do
  describe '.retrieval' do
    it 'builds key from message and agent' do
      key = described_class.retrieval(message: 'how do refunds work?', agent_key: :support_faq)
      expect(key).to include('ai')
      expect(key).to include('support_faq')
      expect(key).to include('how do refunds work')
    end

    it 'produces different keys for different messages' do
      k1 = described_class.retrieval(message: 'refunds', agent_key: :support_faq)
      k2 = described_class.retrieval(message: 'webhooks', agent_key: :support_faq)
      expect(k1).not_to eq(k2)
    end

    it 'produces different keys for different retrieval modes' do
      k1 = described_class.retrieval(message: 'test', agent_key: nil, graph_enabled: false, vector_enabled: false)
      k2 = described_class.retrieval(message: 'test', agent_key: nil, graph_enabled: true, vector_enabled: false)
      expect(k1).not_to eq(k2)
    end
  end

  describe '.tool' do
    it 'includes merchant_id and tool_name' do
      key = described_class.tool(merchant_id: 1, tool_name: 'get_merchant_account', args: {})
      expect(key).to include('ai')
      expect(key).to include('1')
      expect(key).to include('get_merchant_account')
    end

    it 'produces different keys for different merchants' do
      k1 = described_class.tool(merchant_id: 1, tool_name: 'get_merchant_account', args: {})
      k2 = described_class.tool(merchant_id: 2, tool_name: 'get_merchant_account', args: {})
      expect(k1).not_to eq(k2)
    end

    it 'produces different keys for different ledger args' do
      k1 = described_class.tool(merchant_id: 1, tool_name: 'get_ledger_summary', args: { 'preset' => 'last_7_days' })
      k2 = described_class.tool(merchant_id: 1, tool_name: 'get_ledger_summary', args: { 'preset' => 'yesterday' })
      expect(k1).not_to eq(k2)
    end
  end

  describe '.memory' do
    it 'includes session_id and messages_count' do
      key = described_class.memory(session_id: 42, messages_count: 5)
      expect(key).to include('ai')
      expect(key).to include('42')
      expect(key).to include('5')
    end

    it 'produces different keys when message count changes' do
      k1 = described_class.memory(session_id: 1, messages_count: 3)
      k2 = described_class.memory(session_id: 1, messages_count: 4)
      expect(k1).not_to eq(k2)
    end
  end

  describe '.fingerprint' do
    it 'returns 8-char hex for observability' do
      fp = described_class.fingerprint('ai:ret:test:key')
      expect(fp).to match(/\A[a-f0-9]{8}\z/)
    end

    it 'returns nil for blank key' do
      expect(described_class.fingerprint('')).to be_nil
      expect(described_class.fingerprint(nil)).to be_nil
    end
  end
end
