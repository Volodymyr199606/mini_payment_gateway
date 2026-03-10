# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Conversation::CurrentTopicDetector do
  describe '.call' do
    it 'returns nil for empty messages' do
      expect(described_class.call([])).to be_nil
      expect(described_class.call(nil)).to be_nil
    end

    it 'detects refund_flow from keywords' do
      msgs = [{ role: 'user', content: 'How do I issue a refund?' }, { role: 'assistant', content: 'Refunds require...' }]
      expect(described_class.call(msgs)).to eq('refund flow')
    end

    it 'detects webhooks from keywords' do
      msgs = [{ role: 'user', content: 'Set up webhook callback URL for event notifications' }]
      expect(described_class.call(msgs)).to eq('webhooks')
    end

    it 'detects auth_capture from keywords' do
      msgs = [{ role: 'user', content: 'Difference between authorize and capture' }]
      expect(described_class.call(msgs)).to eq('auth capture')
    end

    it 'detects ledger_reporting from keywords' do
      msgs = [{ role: 'user', content: 'Export ledger report for reconciliation' }]
      expect(described_class.call(msgs)).to eq('ledger reporting')
    end

    it 'detects onboarding_api_keys from keywords' do
      msgs = [{ role: 'user', content: 'How do I get started with integration and API key setup?' }]
      expect(described_class.call(msgs)).to eq('onboarding api keys')
    end

    it 'returns nil when no topic keywords match' do
      msgs = [{ role: 'user', content: 'Hello' }, { role: 'assistant', content: 'Hi there' }]
      expect(described_class.call(msgs)).to be_nil
    end

    it 'prefers topic with highest keyword count' do
      msgs = [
        { role: 'user', content: 'refund refund refund webhook' }
      ]
      expect(described_class.call(msgs)).to eq('refund flow')
    end
  end
end
