# frozen_string_literal: true

module Ai
  module Skills
    module Workflows
      # Conservative selection: workflows run only when routing agent + context match explicitly.
      class Selector
        POST_TOOL_PRIORITY = %i[
          reconciliation_analysis_workflow
          payment_explain_with_docs
          webhook_failure_analysis_workflow
        ].freeze

        class << self
          def workflows_enabled?
            ENV['AI_SKILL_WORKFLOWS_DISABLED'].to_s != '1'
          end

          # @param routing_agent_key [Symbol] router / planned agent (not tool-resolved)
          # @param skill_agent [Symbol] InvocationCoordinator.resolve_skill_agent output
          # @param context [InvocationContext]
          # @return [WorkflowDefinition, nil]
          def select_post_tool(routing_agent_key:, skill_agent:, context:)
            return nil unless workflows_enabled?
            return nil unless context.phase == :post_tool

            ak = normalize_routing_agent(routing_agent_key)
            POST_TOOL_PRIORITY.each do |key|
              defn = Registry.fetch(key)
              next unless defn
              next unless defn.allowed_routing_agents.include?(ak)
              next unless matches_post_tool?(defn, ak, skill_agent, context)

              return defn
            end
            nil
          end

          # @return [WorkflowDefinition, nil]
          def select_pre_composition(routing_agent_key:, execution_plan:, followup:, prior_assistant_content:)
            return nil unless workflows_enabled?
            return nil unless execution_plan&.execution_mode == :concise_rewrite_only
            return nil unless prior_assistant_content.present?
            return nil unless followup.is_a?(Hash) && followup[:followup_type] == :explanation_rewrite

            ak = normalize_routing_agent(routing_agent_key)
            defn = Registry.fetch(:rewrite_response_workflow)
            return nil unless defn&.allowed_routing_agents&.include?(ak)

            defn
          end

          def docs_context_message?(message)
            msg = message.to_s.downcase
            msg.match?(/\b(how (do|does|can|to)|what (is|are) (the )?(api|fee|policy|limit)|document|docs?|reference|endpoint|webhook url)\b/)
          end

          def webhook_failure_workflow_eligible?(context)
            return false unless context.has_webhook_data?

            context.has_webhook_retry_relevant_state? || context.has_payment_failure_data?
          end

          private

          def normalize_routing_agent(agent_key)
            return :support_faq if agent_key.blank?

            agent_key.to_sym
          end

          def matches_post_tool?(defn, routing_agent, skill_agent, context)
            case defn.key
            when :reconciliation_analysis_workflow
              routing_agent == :reporting_calculation && context.has_ledger_data? && reconciliation_context_message?(context.message)
            when :payment_explain_with_docs
              (routing_agent == :support_faq || routing_agent == :operational) &&
                context.has_payment_data? &&
                docs_context_message?(context.message)
            when :webhook_failure_analysis_workflow
              routing_agent == :operational && context.has_webhook_data? && webhook_failure_workflow_eligible?(context)
            else
              false
            end
          end

          def reconciliation_context_message?(message)
            msg = message.to_s.downcase
            msg.match?(/\b(reconciliation|discrepancy|mismatch|matching|settlement|payout|statement)\b/)
          end
        end
      end
    end
  end
end
