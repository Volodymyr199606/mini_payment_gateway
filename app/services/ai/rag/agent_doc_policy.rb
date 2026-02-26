# frozen_string_literal: true

module Ai
  module Rag
    # Per-agent policy for RAG: which docs are allowed and preferred when retrieving context.
    # Used to restrict/boost retrieval so citations are relevant to the selected agent.
    class AgentDocPolicy
      # Maps agent symbol => { allowed: [doc paths], preferred: [doc paths] }
      # Paths are relative to repo root (e.g. docs/PAYMENT_LIFECYCLE.md).
      POLICIES = {
        operational: {
          allowed: %w[
            docs/ARCHITECTURE.md
            docs/PAYMENT_LIFECYCLE.md
            docs/DATA_FLOW.md
            docs/SEQUENCE_DIAGRAMS.md
            docs/TIMEOUTS.md
            docs/CHARGEBACKS.md
          ],
          preferred: %w[docs/PAYMENT_LIFECYCLE.md docs/ARCHITECTURE.md docs/DATA_FLOW.md]
        },
        developer_onboarding: {
          allowed: %w[
            docs/REFUNDS_API.md
            docs/TIMEOUTS.md
            docs/SEQUENCE_DIAGRAMS.md
            docs/ARCHITECTURE.md
          ],
          preferred: %w[docs/REFUNDS_API.md docs/ARCHITECTURE.md]
        },
        security_compliance: {
          allowed: %w[docs/SECURITY.md docs/PCI_COMPLIANCE.md],
          preferred: %w[docs/SECURITY.md docs/PCI_COMPLIANCE.md]
        },
        support_faq: {
          allowed: %w[
            docs/ARCHITECTURE.md
            docs/REFUNDS_API.md
            docs/PAYMENT_LIFECYCLE.md
            docs/DATA_FLOW.md
            docs/SECURITY.md
          ],
          preferred: %w[docs/ARCHITECTURE.md docs/REFUNDS_API.md docs/PAYMENT_LIFECYCLE.md]
        },
        reconciliation_analyst: {
          allowed: %w[docs/CHARGEBACKS.md docs/DATA_FLOW.md docs/ARCHITECTURE.md],
          preferred: %w[docs/CHARGEBACKS.md]
        },
        reporting_calculation: {
          allowed: %w[docs/AI_AGENTS.md],
          preferred: %w[docs/AI_AGENTS.md]
        }
      }.freeze

      class << self
        # Returns { allowed: [...], preferred: [...] } for the agent. allowed may be nil (all docs).
        def for_agent(agent_key)
          key = agent_key.to_sym
          policy = POLICIES[key]
          return { allowed: nil, preferred: [] } if policy.nil?

          {
            allowed: policy[:allowed]&.dup,
            preferred: (policy[:preferred] || []).dup
          }
        end

        def allowed_files(agent_key)
          for_agent(agent_key)[:allowed]
        end

        def preferred_files(agent_key)
          for_agent(agent_key)[:preferred]
        end
      end
    end
  end
end
