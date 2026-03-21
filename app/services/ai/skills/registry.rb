# frozen_string_literal: true

module Ai
  module Skills
    # Explicit registration of skills (no autoload discovery). Keys map to BaseSkill subclasses.
    class Registry
      SKILLS = {
        docs_lookup: Builtins::DocsLookupSkill,
        payment_state_explainer: PaymentStateExplainer,
        followup_rewriter: FollowupRewriter,
        webhook_trace_explainer: WebhookTraceExplainer,
        failure_summary: Builtins::FailureSummarySkill,
        ledger_period_summary: LedgerPeriodSummary,
        time_range_resolution: Builtins::TimeRangeResolutionSkill,
        report_explainer: Builtins::ReportExplainerSkill,
        discrepancy_detector: DiscrepancyDetector,
        transaction_trace: Builtins::TransactionTraceSkill
      }.freeze

      DEFINITIONS = SKILLS.transform_values { |klass| klass.definition }.freeze

      class UnknownSkillError < KeyError
        def initialize(key, known)
          super("Unknown skill key: #{key.inspect}. Known: #{known.map(&:inspect).join(', ')}")
        end
      end

      class << self
        def fetch(skill_key)
          key = skill_key.to_sym
          raise UnknownSkillError.new(key, SKILLS.keys) unless SKILLS.key?(key)

          SKILLS[key]
        end

        def known?(skill_key)
          SKILLS.key?(skill_key.to_sym)
        end

        def all_keys
          SKILLS.keys
        end

        def definition(skill_key)
          DEFINITIONS[skill_key.to_sym]
        end

        def definitions
          DEFINITIONS.values
        end

        def validate!
          return true unless Rails.env.development? || Rails.env.test?

          seen = []
          SKILLS.each do |key, klass|
            raise ArgumentError, "Ai::Skills::Registry: duplicate key #{key.inspect}" if seen.include?(key)
            seen << key
            raise ArgumentError, "Ai::Skills::Registry: #{key} must be a Class" unless klass.is_a?(Class)
            raise ArgumentError, "Ai::Skills::Registry: #{key} must inherit BaseSkill" unless klass < BaseSkill && klass != BaseSkill

            defn = klass.definition
            raise ArgumentError, "Ai::Skills::Registry: #{key} definition key mismatch" unless defn.key == key
            raise ArgumentError, "Ai::Skills::Registry: #{key} definition class_name mismatch" unless defn.class_name == klass.name
          end

          raise ArgumentError, 'Ai::Skills::Registry: DEFINITIONS keys must match SKILLS' if DEFINITIONS.keys.sort != SKILLS.keys.sort

          true
        end
      end
    end
  end
end
