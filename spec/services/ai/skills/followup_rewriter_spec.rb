# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Skills::FollowupRewriter do
  describe '#execute' do
    it 'returns failure when prior_assistant_content blank' do
      result = described_class.new.execute(context: { merchant_id: 1 })
      expect(result.failure?).to be true
      expect(result.error_code).to eq('missing_prior')
    end

    it 'returns original when no style requested' do
      prior = 'Payment Intent #42 is captured. Amount: $10.00 USD.'
      result = described_class.new.execute(context: { prior_assistant_content: prior })
      expect(result.success).to be true
      expect(result.data['rewritten_text']).to eq(prior)
      expect(result.data['rewrite_mode']).to eq('none')
    end

    it 'converts to bullet points when style is bullet_points' do
      prior = "First point. Second point. Third point."
      result = described_class.new.execute(
        context: { prior_assistant_content: prior, response_style: [:bullet_points] }
      )
      expect(result.success).to be true
      expect(result.data['rewritten_text']).to include('•')
      expect(result.data['rewrite_mode']).to eq('bullet_points')
    end

    it 'truncates when style is shorter' do
      prior = 'A' * 300
      result = described_class.new.execute(
        context: { prior_assistant_content: prior, response_style: [:shorter] }
      )
      expect(result.success).to be true
      expect(result.data['rewritten_text'].length).to be <= 210
      expect(result.data['rewrite_mode']).to eq('shorter')
    end

    it 'extracts first sentences when style is only_important' do
      prior = "The most critical fact is X. Secondary detail. More details here."
      result = described_class.new.execute(
        context: { prior_assistant_content: prior, response_style: [:only_important] }
      )
      expect(result.success).to be true
      expect(result.data['rewritten_text'].split(/[.!?]/).size).to be <= 3
      expect(result.data['rewrite_mode']).to eq('only_important')
    end

    it 'extracts styles from message when response_style not provided' do
      prior = 'Some explanation text here.'
      result = described_class.new.execute(
        context: {
          prior_assistant_content: prior,
          message: 'Make that simpler and use bullet points'
        }
      )
      expect(result.success).to be true
      expect(result.data['rewritten_text']).to include('•')
    end

    it 'includes audit metadata' do
      result = described_class.new.execute(
        context: {
          prior_assistant_content: 'Text.',
          response_style: [:shorter],
          merchant_id: 1,
          agent_key: 'support_faq'
        }
      )
      expect(result.metadata['agent_key']).to eq('support_faq')
      expect(result.metadata['rewrite_mode']).to be_present
    end
  end
end
