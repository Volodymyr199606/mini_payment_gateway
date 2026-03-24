# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Contract keys for skill usage in audit, debug, replay, and analytics.
      # Used by quality gates; keep in sync with UsageSerializer and InvocationResult#to_audit_hash.
      module SkillMetadataContract
        INVOCATION_RESULT_KEYS = %i[
          skill_key phase invoked reason_code success deterministic
        ].freeze

        USAGE_SERIALIZER_SAFE_KEYS = Ai::Skills::UsageSerializer::SAFE_KEYS.freeze

        COMPOSITION_METADATA_KEYS = %i[
          contributing_skills suppressed_skills suppressed_reason_codes
          filled_response_slots conflict_resolutions precedence_rules_applied
          final_skill_composition_mode style_transform_applied deterministic_primary
        ].freeze

        OPTIONAL_INVOCATION_KEYS = %i[explanation affected_final_response duration_ms].freeze

        # After UsageSerializer.normalize_one, `.compact` may drop nil optional fields.
        MINIMAL_USAGE_KEYS = %w[skill_key phase invoked].freeze

        class << self
          def missing_invocation_keys(hash)
            return ['<empty>'] if hash.blank?

            h = hash.is_a?(Hash) ? hash.with_indifferent_access : {}
            invoked = h[:invoked] == true || h['invoked'] == true
            missing = []
            INVOCATION_RESULT_KEYS.each do |k|
              # Skipped invocations omit nils in to_audit_hash `.compact` (success/deterministic)
              next if !invoked && %i[success deterministic].include?(k)

              missing << k.to_s unless h.key?(k) || h.key?(k.to_s)
            end
            missing
          end

          def invocation_contract_satisfied?(hash)
            missing_invocation_keys(hash).empty?
          end

          def usage_contract_satisfied?(normalized)
            return false if normalized.blank?

            MINIMAL_USAGE_KEYS.all? { |k| normalized.key?(k) }
          end
        end
      end
    end
  end
end
