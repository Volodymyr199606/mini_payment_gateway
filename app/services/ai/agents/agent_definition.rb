# frozen_string_literal: true

module Ai
  module Agents
    # Metadata for a registered agent. Used by AgentRegistry for discovery and capability checks.
    class AgentDefinition
      ALLOWED_PATHS = %w[docs_only tool_plus_docs deterministic_only agent_full no_memory no_retrieval concise_rewrite_only].freeze

      attr_reader :key, :class_name, :description, :allowed_paths,
                  :supports_retrieval, :supports_memory, :supports_orchestration,
                  :preferred_execution_modes, :debug_label, :allowed_skill_keys

      def initialize(
        key:,
        class_name:,
        description: '',
        allowed_paths: ALLOWED_PATHS,
        supports_retrieval: true,
        supports_memory: true,
        supports_orchestration: false,
        preferred_execution_modes: [:agent_full],
        debug_label: nil,
        allowed_skill_keys: []
      )
        @key = key.to_sym
        @class_name = class_name.to_s
        @description = description.to_s
        @allowed_paths = Array(allowed_paths).map(&:to_s).freeze
        @supports_retrieval = !!supports_retrieval
        @supports_memory = !!supports_memory
        @supports_orchestration = !!supports_orchestration
        @preferred_execution_modes = Array(preferred_execution_modes).map(&:to_sym).freeze
        @debug_label = (debug_label || key.to_s).to_s
        @allowed_skill_keys = Array(allowed_skill_keys).map(&:to_sym).freeze
      end

      def supports_retrieval?
        @supports_retrieval
      end

      def supports_memory?
        @supports_memory
      end

      def supports_orchestration?
        @supports_orchestration
      end

      def allowed_skill?(skill_key)
        @allowed_skill_keys.include?(skill_key.to_sym)
      end

      def to_h
        {
          key: @key,
          class_name: @class_name,
          description: @description,
          allowed_paths: @allowed_paths,
          supports_retrieval: @supports_retrieval,
          supports_memory: @supports_memory,
          supports_orchestration: @supports_orchestration,
          preferred_execution_modes: @preferred_execution_modes,
          debug_label: @debug_label,
          allowed_skill_keys: @allowed_skill_keys
        }
      end
    end
  end
end
