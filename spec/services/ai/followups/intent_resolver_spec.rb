# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Followups::IntentResolver do
  def msg(role, content)
    { role: role, content: content }
  end

  describe 'time-range follow-up resolution' do
    it 'returns get_ledger_summary with yesterday when prior was ledger and current says "What about yesterday?"' do
      recent = [
        msg('user', 'What is my net volume for last 7 days?'),
        msg('assistant', 'Your net volume is $1,234.'),
        msg('user', 'What about yesterday?')
      ]
      result = described_class.call(message: 'What about yesterday?', recent_messages: recent)
      expect(result[:intent]).to be_present
      expect(result[:intent][:tool_name]).to eq('get_ledger_summary')
      expect(result[:intent][:args][:from]).to be_present
      expect(result[:intent][:args][:to]).to be_present
      expect(result[:followup][:followup_type]).to eq(:time_range_adjustment)
    end
  end

  describe 'entity follow-up resolution' do
    it 'returns get_payment_intent with inherited id when prior had pi_123 and current says "Was it captured?"' do
      recent = [
        msg('user', 'Status of payment intent 456?'),
        msg('assistant', 'Payment intent 456 is authorized.'),
        msg('user', 'Was it captured after that?')
      ]
      result = described_class.call(message: 'Was it captured after that?', recent_messages: recent)
      expect(result[:intent]).to be_present
      expect(result[:intent][:tool_name]).to eq('get_payment_intent')
      expect(result[:intent][:args][:payment_intent_id]).to eq(456)
    end
  end

  describe 'explicit intent overrides follow-up' do
    it 'uses explicit payment intent in current message over prior' do
      recent = [
        msg('user', 'Status of payment intent 123?'),
        msg('assistant', 'Authorized.'),
        msg('user', 'What about payment intent 789?')
      ]
      result = described_class.call(message: 'What about payment intent 789?', recent_messages: recent)
      expect(result[:intent][:tool_name]).to eq('get_payment_intent')
      expect(result[:intent][:args][:payment_intent_id]).to eq(789)
    end
  end

  describe 'explanation rewrite does not force tool' do
    it 'returns nil intent for "Explain that more simply"' do
      recent = [
        msg('user', 'How do refunds work?'),
        msg('assistant', 'Refunds reverse a capture...'),
        msg('user', 'Explain that more simply')
      ]
      result = described_class.call(message: 'Explain that more simply', recent_messages: recent)
      expect(result[:intent]).to be_nil
      expect(result[:followup][:followup_type]).to eq(:explanation_rewrite)
    end
  end

  describe 'ambiguous follow-up stays conservative' do
    it 'returns nil intent when prior had no clear tool' do
      recent = [
        msg('user', 'Hello'),
        msg('assistant', 'Hi!'),
        msg('user', 'that')
      ]
      result = described_class.call(message: 'that', recent_messages: recent)
      expect(result[:intent]).to be_nil
    end
  end
end
