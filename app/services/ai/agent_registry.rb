# frozen_string_literal: true

module Ai
  # Registry of agents: key => class, plus optional metadata (AgentDefinition).
  # Single source of truth for agent discovery. Use .fetch(key) for resolution.
  class AgentRegistry
    REGISTRY = {
      support_faq: Agents::SupportFaqAgent,
      security_compliance: Agents::SecurityAgent,
      developer_onboarding: Agents::OnboardingAgent,
      operational: Agents::OperationalAgent,
      reconciliation_analyst: Agents::ReconciliationAgent,
      reporting_calculation: Agents::ReportingCalculationAgent
    }.freeze

    DEFINITIONS = {
      support_faq: Agents::AgentDefinition.new(
        key: :support_faq,
        class_name: 'Ai::Agents::SupportFaqAgent',
        description: 'Support/FAQ agent. Answers refunds, payment statuses, API usage.',
        supports_retrieval: true,
        supports_memory: true,
        debug_label: 'Support FAQ'
      ),
      security_compliance: Agents::AgentDefinition.new(
        key: :security_compliance,
        class_name: 'Ai::Agents::SecurityAgent',
        description: 'Security/compliance. PCI, tokenization, webhook signatures.',
        supports_retrieval: true,
        supports_memory: false,
        debug_label: 'Security'
      ),
      developer_onboarding: Agents::AgentDefinition.new(
        key: :developer_onboarding,
        class_name: 'Ai::Agents::OnboardingAgent',
        description: 'Developer onboarding. Integration, idempotency, webhooks, API.',
        supports_retrieval: true,
        supports_memory: false,
        debug_label: 'Developer'
      ),
      operational: Agents::AgentDefinition.new(
        key: :operational,
        class_name: 'Ai::Agents::OperationalAgent',
        description: 'Operational. Payment lifecycle, statuses, chargebacks.',
        supports_retrieval: true,
        supports_memory: false,
        debug_label: 'Operational'
      ),
      reconciliation_analyst: Agents::AgentDefinition.new(
        key: :reconciliation_analyst,
        class_name: 'Ai::Agents::ReconciliationAgent',
        description: 'Reconciliation design guidance. Not implemented yet.',
        supports_retrieval: true,
        supports_memory: false,
        debug_label: 'Reconciliation'
      ),
      reporting_calculation: Agents::AgentDefinition.new(
        key: :reporting_calculation,
        class_name: 'Ai::Agents::ReportingCalculationAgent',
        description: 'Reporting/ledger. Uses deterministic ledger tool.',
        supports_retrieval: false,
        supports_memory: false,
        supports_orchestration: false,
        preferred_execution_modes: [:deterministic_only],
        debug_label: 'Reporting'
      )
    }.freeze

    class UnknownAgentError < KeyError
      def initialize(key, known)
        super("Unknown agent key: #{key.inspect}. Known keys: #{known.map(&:inspect).join(', ')}")
      end
    end

    class << self
      def fetch(agent_key)
        key = agent_key.to_sym
        raise UnknownAgentError.new(key, REGISTRY.keys) unless REGISTRY.key?(key)

        REGISTRY[key]
      end

      def all_keys
        REGISTRY.keys
      end

      def default_key
        :support_faq
      end

      def definition(agent_key)
        DEFINITIONS[agent_key.to_sym]
      end

      def definitions
        DEFINITIONS.values
      end

      def validate!
        return true unless Rails.env.development? || Rails.env.test?

        seen = []
        REGISTRY.each do |key, klass|
          raise ArgumentError, "AgentRegistry: duplicate key #{key.inspect}" if seen.include?(key)
          seen << key
          raise ArgumentError, "AgentRegistry: #{key} class #{klass} not found" unless klass.is_a?(Class)
        end
        raise ArgumentError, "AgentRegistry: DEFINITIONS keys must match REGISTRY" if DEFINITIONS.keys.sort != REGISTRY.keys.sort
        DEFINITIONS.each_value do |defn|
          raise ArgumentError, "AgentRegistry: definition key #{defn.key} missing class_name" if defn.class_name.blank?
        end
        true
      end
    end
  end
end
