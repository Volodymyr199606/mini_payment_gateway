# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::MessageSanitizer do
  describe '.sanitize' do
    it 'redacts api_key= style values' do
      text = 'My api_key=sk_live_abc123def456ghi789 and more'
      expect(described_class.sanitize(text)).to include('[REDACTED]')
      expect(described_class.sanitize(text)).not_to include('sk_live_abc123def456ghi789')
    end

    it 'redacts Bearer token style values' do
      text = 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xxx'
      expect(described_class.sanitize(text)).to include('[REDACTED]')
      expect(described_class.sanitize(text)).not_to include('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9')
    end

    it 'redacts long hex strings (e.g. API key hashes)' do
      text = 'Use key a1b2c3d4e5f6789012345678901234567890abcd'
      expect(described_class.sanitize(text)).to include('[REDACTED]')
      expect(described_class.sanitize(text)).not_to include('a1b2c3d4e5f6789012345678901234567890abcd')
    end

    it 'redacts token= and secret= param-style values' do
      text = 'token=super_secret_value_here_123'
      expect(described_class.sanitize(text)).to include('[REDACTED]')
      expect(described_class.sanitize(text)).not_to include('super_secret_value_here_123')
    end

    it 'leaves normal content unchanged' do
      text = 'User asked about refunds and authorize vs capture.'
      expect(described_class.sanitize(text)).to eq(text)
    end

    it 'returns empty string for blank input' do
      expect(described_class.sanitize('')).to eq('')
      expect(described_class.sanitize(nil)).to eq('')
    end
  end
end
