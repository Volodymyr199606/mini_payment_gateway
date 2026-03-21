# frozen_string_literal: true

module Ai
  module Skills
    # Registered stub skills: explicit placeholders until orchestration wires real behavior.
    # Each returns a deterministic SkillResult suitable for framework and audit tests.
    module Builtins
      class DocsLookupSkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :docs_lookup,
          class_name: 'Ai::Skills::Builtins::DocsLookupSkill',
          description: 'Ground answers in internal documentation (RAG / retrieval).',
          deterministic: true,
          dependencies: %i[retrieval context],
          input_contract: 'user message, optional agent and merchant context',
          output_contract: 'SkillResult with retrieval hints or composed context'
        )

        def execute(context:)
          stub_skill_result(skill_key: :docs_lookup, definition: self.class.definition, context: context)
        end
      end

      class PaymentStateExplainerSkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :payment_state_explainer,
          class_name: 'Ai::Skills::Builtins::PaymentStateExplainerSkill',
          description: 'Explain payment intent lifecycle states using domain semantics.',
          deterministic: true,
          dependencies: %i[context tools],
          input_contract: 'message, optional entity ids',
          output_contract: 'SkillResult with structured explanation payload'
        )

        def execute(context:)
          stub_skill_result(skill_key: :payment_state_explainer, definition: self.class.definition, context: context)
        end
      end

      class FollowupRewriterSkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :followup_rewriter,
          class_name: 'Ai::Skills::Builtins::FollowupRewriterSkill',
          description: 'Rewrite or clarify follow-up questions safely.',
          deterministic: false,
          dependencies: %i[memory context],
          input_contract: 'prior turn summary, current message',
          output_contract: 'SkillResult with rewritten query text'
        )

        def execute(context:)
          stub_skill_result(skill_key: :followup_rewriter, definition: self.class.definition, context: context)
        end
      end

      class WebhookTraceExplainerSkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :webhook_trace_explainer,
          class_name: 'Ai::Skills::Builtins::WebhookTraceExplainerSkill',
          description: 'Explain webhook delivery and status from merchant data.',
          deterministic: true,
          dependencies: %i[tools context],
          input_contract: 'webhook id or message',
          output_contract: 'SkillResult with trace summary'
        )

        def execute(context:)
          stub_skill_result(skill_key: :webhook_trace_explainer, definition: self.class.definition, context: context)
        end
      end

      class FailureSummarySkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :failure_summary,
          class_name: 'Ai::Skills::Builtins::FailureSummarySkill',
          description: 'Summarize failed transactions or operations.',
          deterministic: true,
          dependencies: %i[tools context],
          input_contract: 'time range or entity ids',
          output_contract: 'SkillResult with failure aggregates'
        )

        def execute(context:)
          stub_skill_result(skill_key: :failure_summary, definition: self.class.definition, context: context)
        end
      end

      class LedgerPeriodSummarySkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :ledger_period_summary,
          class_name: 'Ai::Skills::Builtins::LedgerPeriodSummarySkill',
          description: 'Summarize ledger for a time period (deterministic tool path).',
          deterministic: true,
          dependencies: %i[tools context],
          input_contract: 'resolved time range, merchant scope',
          output_contract: 'SkillResult with ledger summary data'
        )

        def execute(context:)
          stub_skill_result(skill_key: :ledger_period_summary, definition: self.class.definition, context: context)
        end
      end

      class TimeRangeResolutionSkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :time_range_resolution,
          class_name: 'Ai::Skills::Builtins::TimeRangeResolutionSkill',
          description: 'Resolve natural language time ranges to concrete bounds.',
          deterministic: true,
          dependencies: %i[context],
          input_contract: 'message text',
          output_contract: 'SkillResult with from/to timestamps'
        )

        def execute(context:)
          stub_skill_result(skill_key: :time_range_resolution, definition: self.class.definition, context: context)
        end
      end

      class ReportExplainerSkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :report_explainer,
          class_name: 'Ai::Skills::Builtins::ReportExplainerSkill',
          description: 'Explain reporting and ledger metrics to the user.',
          deterministic: false,
          dependencies: %i[tools context retrieval],
          input_contract: 'message, optional ledger summary',
          output_contract: 'SkillResult with narrative explanation'
        )

        def execute(context:)
          stub_skill_result(skill_key: :report_explainer, definition: self.class.definition, context: context)
        end
      end

      class DiscrepancyDetectorSkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :discrepancy_detector,
          class_name: 'Ai::Skills::Builtins::DiscrepancyDetectorSkill',
          description: 'Highlight potential reconciliation discrepancies (design guidance).',
          deterministic: false,
          dependencies: %i[tools context],
          input_contract: 'ledger summary or transaction ids',
          output_contract: 'SkillResult with discrepancy hints'
        )

        def execute(context:)
          stub_skill_result(skill_key: :discrepancy_detector, definition: self.class.definition, context: context)
        end
      end

      class TransactionTraceSkill < BaseSkill
        DEFINITION = SkillDefinition.new(
          key: :transaction_trace,
          class_name: 'Ai::Skills::Builtins::TransactionTraceSkill',
          description: 'Trace a transaction across related records.',
          deterministic: true,
          dependencies: %i[tools context],
          input_contract: 'transaction id',
          output_contract: 'SkillResult with trace graph or list'
        )

        def execute(context:)
          stub_skill_result(skill_key: :transaction_trace, definition: self.class.definition, context: context)
        end
      end
    end
  end
end
