# frozen_string_literal: true

module Ai
  module Skills
    module Workflows
      # Stable metadata for a bounded multi-skill workflow run (audit, debug, replay, analytics).
      # Bump `CONTRACT_SCHEMA_VERSION` only with `Ai::Skills::PlatformV1::CONTRACT_SCHEMA_VERSION`.
      class WorkflowResult
        CONTRACT_SCHEMA_VERSION = '1.0.0'

        attr_reader :workflow_key, :workflow_selected, :steps_attempted, :steps_completed,
                    :contributing_skills, :skipped_skills, :stop_reason, :success,
                    :affected_final_response, :metadata, :duration_ms

        STOP_REASONS = %w[
          completed
          profile_budget_reached
          profile_heavy_budget_reached
          prerequisite_missing
          skill_not_allowed
          skill_execution_failed
          workflow_disabled
          max_steps_reached
          selection_mismatch
        ].freeze

        def initialize(
          workflow_key:,
          workflow_selected: false,
          steps_attempted: 0,
          steps_completed: 0,
          contributing_skills: [],
          skipped_skills: [],
          stop_reason: 'completed',
          success: true,
          affected_final_response: false,
          metadata: {},
          duration_ms: nil
        )
          @workflow_key = workflow_key.to_s.presence
          @workflow_selected = !!workflow_selected
          @steps_attempted = steps_attempted.to_i
          @steps_completed = steps_completed.to_i
          @contributing_skills = Array(contributing_skills).map(&:to_s)
          @skipped_skills = Array(skipped_skills).map(&:to_s)
          @stop_reason = stop_reason.to_s.presence || 'completed'
          @success = !!success
          @affected_final_response = !!affected_final_response
          @metadata = metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
          @duration_ms = duration_ms&.to_i&.positive? ? duration_ms.to_i : nil
        end

        def to_audit_hash
          {
            workflow_key: @workflow_key,
            workflow_selected: @workflow_selected,
            steps_attempted: @steps_attempted,
            steps_completed: @steps_completed,
            contributing_skills: @contributing_skills.presence,
            skipped_skills: @skipped_skills.presence,
            stop_reason: @stop_reason,
            success: @success,
            affected_final_response: @affected_final_response,
            duration_ms: @duration_ms
          }.merge(@metadata).compact
        end

        def self.none
          new(workflow_key: nil, workflow_selected: false, stop_reason: 'workflow_disabled', success: true)
        end
      end
    end
  end
end
