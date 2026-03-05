# frozen_string_literal: true

module Ai
  # Single registry mapping agent_key (symbol) to agent class.
  # Use .fetch(key) for resolution; raises on unknown key.
  class AgentRegistry
    REGISTRY = {
      support_faq: Agents::SupportFaqAgent,
      security_compliance: Agents::SecurityAgent,
      developer_onboarding: Agents::OnboardingAgent,
      operational: Agents::OperationalAgent,
      reconciliation_analyst: Agents::ReconciliationAgent,
      reporting_calculation: Agents::ReportingCalculationAgent
    }.freeze

    class UnknownAgentError < KeyError
      def initialize(key, known)
        super("Unknown agent key: #{key.inspect}. Known keys: #{known.map(&:inspect).join(', ')}")
      end
    end

    def self.fetch(agent_key)
      key = agent_key.to_sym
      raise UnknownAgentError.new(key, REGISTRY.keys) unless REGISTRY.key?(key)

      REGISTRY[key]
    end

    def self.all_keys
      REGISTRY.keys
    end

    def self.default_key
      :support_faq
    end
  end
end
