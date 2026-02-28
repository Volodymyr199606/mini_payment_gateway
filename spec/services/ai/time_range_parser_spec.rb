# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TimeRangeParser do
  it 'parses supported phrases' do
    expect { described_class.parse('today') }.not_to raise_error
    expect { described_class.parse('yesterday') }.not_to raise_error
    expect { described_class.parse('last 7 days') }.not_to raise_error
    expect { described_class.parse('last week') }.not_to raise_error
    expect { described_class.parse('this month') }.not_to raise_error
    expect { described_class.parse('last month') }.not_to raise_error
    expect { described_class.parse('all time') }.not_to raise_error
    expect { described_class.parse('all-time') }.not_to raise_error
  end

  it 'returns [from, to] for today (in America/Los_Angeles)' do
    from, to = described_class.parse('today')
    today_la = ActiveSupport::TimeZone[described_class::TIMEZONE].now.to_date
    expect(from).to be <= to
    expect(from.to_date).to eq(today_la)
    expect(to.to_date).to eq(today_la)
  end

  it 'raises ParseError for unsupported phrase' do
    expect { described_class.parse('next year') }.to raise_error(Ai::TimeRangeParser::ParseError, /Unsupported/)
  end

  describe '.extract_and_parse' do
    it 'defaults to all-time with inferred true when no time phrase in message' do
      result = described_class.extract_and_parse('how much refunded?')

      expect(result[:inferred]).to be true
      expect(result[:default_used]).to eq('all_time')
      expect(result[:from]).to be <= described_class::ALL_TIME_START
      expect(result[:to]).to be >= result[:from]
      expect(result[:range_label]).to include('(all-time)')
    end

    it 'returns correct date range and inferred false when explicit phrase present' do
      result = described_class.extract_and_parse('how much refunded last 7 days?')

      expect(result[:inferred]).to be false
      expect(result[:default_used]).to be_nil
      expect(result[:range_label]).to eq('last 7 days')
      from_date = result[:from].to_date
      to_date = result[:to].to_date
      expect(to_date - from_date).to be <= 7
    end
  end
end
