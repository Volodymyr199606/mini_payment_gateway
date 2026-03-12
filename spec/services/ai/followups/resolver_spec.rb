# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Followups::Resolver do
  def call(current_message, recent_messages)
    described_class.call(current_message: current_message, recent_messages: recent_messages)
  end

  def msg(role, content, agent: nil)
    h = { role: role, content: content }
    h[:agent] = agent if agent
    h
  end

  describe 'when no recent messages' do
    it 'returns followup_detected false' do
      result = call('What about yesterday?', [])
      expect(result[:followup_detected]).to be false
    end
  end

  describe 'when only one turn' do
    it 'returns followup_detected false' do
      recent = [msg('user', 'Show my net volume'), msg('assistant', 'Here is your net volume.')]
      result = call('What about yesterday?', recent)
      expect(result[:followup_detected]).to be false
    end
  end

  describe 'time_range_adjustment' do
    it 'detects "What about yesterday?" after reporting question' do
      recent = [
        msg('user', 'What is my net volume for last 7 days?'),
        msg('assistant', 'Your net volume for last 7 days is $1,234.'),
        msg('user', 'What about yesterday?')
      ]
      result = call('What about yesterday?', recent)
      expect(result[:followup_detected]).to be true
      expect(result[:followup_type]).to eq(:time_range_adjustment)
      expect(result[:inherited_time_range]).to be_present
      expect(result[:inherited_time_range][:range_label]).to eq('yesterday')
    end

    it 'detects "Do the same for last week"' do
      recent = [
        msg('user', 'Show me total refunds last month'),
        msg('assistant', 'Total refunds: $500.'),
        msg('user', 'Do the same for last week')
      ]
      result = call('Do the same for last week', recent)
      expect(result[:followup_detected]).to be true
      expect(result[:followup_type]).to eq(:time_range_adjustment)
      expect(result[:inherited_time_range][:range_label]).to eq('last week')
    end
  end

  describe 'entity_followup' do
    it 'detects "Was it captured after that?" and inherits entities from prior user' do
      recent = [
        msg('user', 'What is the status of payment intent 123?'),
        msg('assistant', 'Payment intent 123 is authorized.'),
        msg('user', 'Was it captured after that?')
      ]
      result = call('Was it captured after that?', recent)
      expect(result[:followup_detected]).to be true
      expect(result[:followup_type]).to eq(:entity_followup)
      expect(result[:inherited_entities][:payment_intent_id]).to eq(123)
    end
  end

  describe 'result_filtering' do
    it 'detects "Only failed ones" after list query' do
      recent = [
        msg('user', 'Show me captures from last week'),
        msg('assistant', 'Here are the captures.'),
        msg('user', 'Only failed ones')
      ]
      result = call('Only failed ones', recent)
      expect(result[:followup_detected]).to be true
      expect(result[:followup_type]).to eq(:result_filtering)
    end
  end

  describe 'explanation_rewrite' do
    it 'detects "Explain that more simply"' do
      recent = [
        msg('user', 'How do refunds work?'),
        msg('assistant', 'Refunds reverse a capture...'),
        msg('user', 'Explain that more simply')
      ]
      result = call('Explain that more simply', recent)
      expect(result[:followup_detected]).to be true
      expect(result[:followup_type]).to eq(:explanation_rewrite)
      expect(result[:response_style_adjustments]).to include(:simpler)
    end
  end

  describe 'ambiguous follow-ups' do
    it 'returns conservative result for very ambiguous "that"' do
      recent = [
        msg('user', 'Hello'),
        msg('assistant', 'Hi!'),
        msg('user', 'that')
      ]
      result = call('that', recent)
      expect(result[:followup_detected]).to be true
      expect(result[:followup_type]).to eq(:ambiguous_followup)
      expect(result[:confidence]).to be <= 0.6
    end
  end

  describe 'no inheritance when inappropriate' do
    it 'does not detect follow-up for long standalone message' do
      recent = [
        msg('user', 'What is the status of payment intent 123?'),
        msg('assistant', 'Authorized.'),
        msg('user', 'I need to understand the full payment lifecycle from authorization through capture and refund, including webhook notifications and idempotency')
      ]
      result = call('I need to understand the full payment lifecycle from authorization through capture and refund, including webhook notifications and idempotency', recent)
      expect(result[:followup_detected]).to be false
    end
  end
end
