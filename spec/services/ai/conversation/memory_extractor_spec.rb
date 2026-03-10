# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Conversation::MemoryExtractor do
  describe '.call' do
    it 'returns all nil for blank summary' do
      result = described_class.call('')
      expect(result[:current_topic]).to be_nil
      expect(result[:user_preferences]).to be_nil
      expect(result[:open_tasks]).to be_nil
    end

    it 'extracts user preferences section' do
      summary = <<~TEXT
        ## Current topic
        - Refunds
        ## Facts
        - User asked about refunds.
        ## User preferences
        - Prefers email notifications.
        - Wants JSON responses.
        ## Open tasks
        - None.
      TEXT
      result = described_class.call(summary)
      expect(result[:user_preferences]).to include('Prefers email')
      expect(result[:user_preferences]).to include('JSON')
    end

    it 'extracts open tasks section' do
      summary = <<~TEXT
        ## Facts
        - Discussed webhooks.
        ## User preferences
        - None.
        ## Open tasks
        - Verify webhook signature.
        - Test in sandbox.
      TEXT
      result = described_class.call(summary)
      expect(result[:open_tasks]).to include('Verify webhook')
      expect(result[:open_tasks]).to include('Test in sandbox')
    end

    it 'extracts current topic from summary' do
      summary = <<~TEXT
        ## Current topic
        - Webhook configuration
        ## Facts
        - User setting up webhooks.
      TEXT
      result = described_class.call(summary)
      expect(result[:current_topic]).to include('Webhook configuration')
    end

    it 'returns nil for absent sections' do
      summary = "## Facts\n- Only facts here."
      result = described_class.call(summary)
      expect(result[:current_topic]).to be_nil
      expect(result[:user_preferences]).to be_nil
      expect(result[:open_tasks]).to be_nil
      expect(result[:facts]).to be_present
    end
  end
end
