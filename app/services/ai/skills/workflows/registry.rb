# frozen_string_literal: true

module Ai
  module Skills
    module Workflows
      # Explicit registration of allowed bounded workflows. No runtime discovery.
      class Registry
        MAX_WORKFLOW_STEPS = WorkflowDefinition::MAX_SKILL_STEPS

        class << self
          def definitions
            @definitions ||= build_definitions.freeze
          end

          def fetch(key)
            definitions[key.to_sym]
          end

          def keys
            definitions.keys
          end

          # Raises if duplicate keys or invalid — call from tests / initializer optional
          def validate!
            seen = {}
            definitions.each do |k, defn|
              raise "duplicate workflow #{k}" if seen[k]

              seen[k] = true
              raise "empty steps: #{k}" if defn.skill_steps.empty?
              raise "too many steps: #{k}" if defn.skill_steps.size > MAX_WORKFLOW_STEPS
            end
            true
          end

          private

          def build_definitions
            {
              payment_explain_with_docs: WorkflowDefinition.new(
                key: :payment_explain_with_docs,
                description: 'Deterministic payment explanation, then optional docs clarification for support queries.',
                skill_steps: %i[payment_state_explainer docs_lookup],
                allowed_routing_agents: %i[support_faq],
                execution_agent_key: :support_faq,
                phase: :post_tool
              ),
              reconciliation_analysis_workflow: WorkflowDefinition.new(
                key: :reconciliation_analysis_workflow,
                description: 'Ledger-backed discrepancy scan then bounded reconciliation next steps.',
                skill_steps: %i[discrepancy_detector reconciliation_action_summary],
                allowed_routing_agents: %i[reconciliation_analyst],
                execution_agent_key: :reconciliation_analyst,
                phase: :post_tool
              ),
              webhook_failure_analysis_workflow: WorkflowDefinition.new(
                key: :webhook_failure_analysis_workflow,
                description: 'Webhook trace explanation then payment failure summary when failure context applies.',
                skill_steps: %i[webhook_trace_explainer payment_failure_summary],
                allowed_routing_agents: %i[operational],
                execution_agent_key: :operational,
                phase: :post_tool
              ),
              rewrite_response_workflow: WorkflowDefinition.new(
                key: :rewrite_response_workflow,
                description: 'Style-focused rewrite of prior assistant content (concise rewrite path).',
                skill_steps: %i[followup_rewriter],
                allowed_routing_agents: %i[support_faq developer_onboarding],
                execution_agent_key: nil,
                phase: :pre_composition
              )
            }
          end
        end
      end
    end
  end
end
