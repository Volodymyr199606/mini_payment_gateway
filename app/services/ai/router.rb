# frozen_string_literal: true

module Ai
  # Selects specialist agent from message using keyword heuristics.
  # Returns symbol: :support_faq, :security_compliance, :developer_onboarding, :operational, :reconciliation_analyst
  class Router
    # Order matters: first match wins. Reporting uses phrase match to avoid catching "how" in "how do I".
    REPORTING_PHRASES = [
      'how much', 'last 7 days', 'last week', 'this month', 'last month', 'yesterday',
      'refund volume', 'net balance', 'total charges', 'total refunds', 'total fees'
    ].freeze
    KEYWORDS = {
      reporting_calculation: %w[total sum spent fees net balance], # phrase check runs first
      security_compliance: %w[pci pan cvv token log signature compliance secure],
      developer_onboarding: %w[idempotency integrate curl endpoint api key webhook post get request],
      operational: %w[status refund void authorize capture payment intent lifecycle chargeback dispute],
      reconciliation_analyst: %w[reconciliation settlement payout matching statement]
    }.freeze

    def initialize(message)
      @message = message.to_s.downcase
    end

    def call
      return :reporting_calculation if REPORTING_PHRASES.any? { |phrase| @message.include?(phrase) }
      KEYWORDS.each do |agent, words|
        return agent if words.any? { |w| @message.include?(w) }
      end
      :support_faq
    end
  end
end
