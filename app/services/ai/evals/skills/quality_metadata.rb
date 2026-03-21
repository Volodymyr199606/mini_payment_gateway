# frozen_string_literal: true

module Ai
  module Evals
    module Skills
      # Stable quality metadata shape for skill evaluation and quality gates.
      # Internal use; safe for tests, replay comparison, and analytics.
      module QualityMetadata
        KEYS = %w[
          skill_expected skill_invoked skill_helpful skill_blocked_by_policy
          skill_unnecessary skill_affected_response skill_quality_notes
        ].freeze

        class << self
          # @param skill_key [String, Symbol]
          # @param invoked [Boolean]
          # @param helpful [Boolean] whether skill output was used in final response
          # @param opts [Hash] optional fields
          # @return [Hash] normalized quality metadata
          def build(skill_key:, invoked:, helpful: nil, **opts)
            {
              'skill_key' => skill_key.to_s,
              'skill_invoked' => !!invoked,
              'skill_helpful' => helpful,
              'skill_blocked_by_policy' => !!opts[:skill_blocked_by_policy],
              'skill_unnecessary' => !!opts[:skill_unnecessary],
              'skill_affected_response' => !!opts[:skill_affected_response],
              'skill_quality_notes' => opts[:skill_quality_notes].to_s.strip.presence
            }.compact
          end

          # @param invocation_results [Array<Hash>]
          # @param skill_affected_reply [Boolean]
          # @return [Array<Hash>] quality metadata per skill
          def from_invocation_results(invocation_results:, skill_affected_reply: false)
            return [] if invocation_results.blank?

            invocation_results.map do |r|
              skill_key = r[:skill_key] || r['skill_key']
              invoked = r[:invoked] || r['invoked']
              success = r[:success] || r['success']
              build(
                skill_key: skill_key,
                invoked: invoked,
                helpful: invoked && success,
                skill_affected_response: invoked && success && skill_affected_reply
              )
            end
          end
        end
      end
    end
  end
end
