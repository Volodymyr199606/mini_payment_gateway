# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Resilience::Decision do
  describe '.normal' do
    it 'returns non-degraded decision' do
      d = described_class.normal
      expect(d.degraded?).to be false
      expect(d.failure_stage).to be_nil
      expect(d.fallback_mode).to eq(:normal)
      expect(d.safe_message).to be_nil
    end
  end

  describe '.degrade' do
    it 'returns degraded decision with stage and fallback' do
      d = described_class.degrade(
        failure_stage: :generation,
        fallback_mode: :safe_failure_message,
        safe_message: 'Try again later'
      )
      expect(d.degraded?).to be true
      expect(d.failure_stage).to eq(:generation)
      expect(d.fallback_mode).to eq(:safe_failure_message)
      expect(d.safe_message).to eq('Try again later')
    end
  end
end
