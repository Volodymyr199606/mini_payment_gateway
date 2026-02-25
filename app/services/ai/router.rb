# frozen_string_literal: true

module Ai
  # Selects specialist agent from message using keyword heuristics.
  # Returns symbol: :support_faq, :security_compliance, :developer_onboarding, :operational, :reconciliation_analyst
  class Router
    # Order matters: first match wins. developer_onboarding before security so "webhook" alone hits onboarding.
    KEYWORDS = {
      security_compliance: %w[pci pan cvv token log signature compliance secure],
      developer_onboarding: %w[idempotency integrate curl endpoint api key webhook post get request],
      operational: %w[status refund void authorize capture payment intent lifecycle chargeback dispute],
      reconciliation_analyst: %w[reconciliation settlement payout matching statement]
    }.freeze

    def initialize(message)
      @message = message.to_s.downcase
    end

    def call
      KEYWORDS.each do |agent, words|
        return agent if words.any? { |w| @message.include?(w) }
      end
      :support_faq
    end
  end
end
