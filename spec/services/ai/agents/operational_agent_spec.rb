# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::OperationalAgent do
  describe '#call' do
    let(:context_text) do
      <<~TEXT
        ---
        [docs/PAYMENT_LIFECYCLE.md :: Authorize vs Capture]
        **Authorize:** Request to hold the payment amount. On success, status becomes authorized. No ledger entry.
        **Capture:** Request to settle the authorized amount. On success, status becomes captured. A ledger entry (charge) is created.
        Ledger entries are created only on capture and refund, not on authorize or void.
      TEXT
    end
    let(:citations) { [{ file: 'docs/PAYMENT_LIFECYCLE.md', heading: 'Authorize vs Capture', anchor: 'authorize-vs-capture', excerpt: '...' }] }

    it 'reply includes structured Authorize and Capture and mentions ledger entry timing (capture/refund)' do
      structured_reply = <<~REPLY
        In this system, authorize holds funds and capture settles them.

        **Authorize**
        - Hold the payment amount; no money moves to the merchant.
        - Status impact: created → authorized (on success).
        - Ledger impact: no ledger entry.

        **Capture**
        - Settle the previously authorized amount.
        - Status impact: authorized → captured (on success).
        - Ledger impact: ledger entry (charge) created. In this project, ledger entries are created only on capture and refund, not on authorize or void (docs/PAYMENT_LIFECYCLE.md).
      REPLY
      client = instance_double(Ai::GroqClient, chat: { content: structured_reply, model_used: 'test', fallback_used: false })
      allow(Ai::GroqClient).to receive(:new).and_return(client)

      agent = described_class.new(message: 'Explain authorize vs capture', context_text: context_text, citations: citations)
      out = agent.call

      reply = out[:reply]
      expect(reply).to include('Authorize')
      expect(reply).to include('Capture')
      expect(reply).to include('ledger')
      expect(reply).to satisfy { |r| r.include?('capture') && r.include?('refund') }
    end
  end
end
