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
  end

  it 'returns [from, to] for today' do
    from, to = described_class.parse('today')
    expect(from).to be <= to
    expect(from.to_date).to eq(Time.zone.now.to_date)
    expect(to.to_date).to eq(Time.zone.now.to_date)
  end

  it 'raises ParseError for unsupported phrase' do
    expect { described_class.parse('next year') }.to raise_error(Ai::TimeRangeParser::ParseError, /Unsupported/)
  end
end
