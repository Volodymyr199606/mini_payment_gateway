# frozen_string_literal: true

module Ai
  module Tools
    # Metadata for a registered tool. Used by Registry for discovery and capability checks.
    class ToolDefinition
      attr_reader :key, :class_name, :description, :read_only,
                  :requires_merchant_scope, :allowed_intent_types, :allowed_agents,
                  :allowed_execution_modes, :cacheable

      def initialize(
        key:,
        class_name:,
        description: '',
        read_only: true,
        requires_merchant_scope: true,
        allowed_intent_types: nil,
        allowed_agents: nil,
        allowed_execution_modes: nil,
        cacheable: false
      )
        @key = key.to_s
        @class_name = class_name.to_s
        @description = description.to_s
        @read_only = read_only
        @requires_merchant_scope = !!requires_merchant_scope
        @allowed_intent_types = allowed_intent_types ? Array(allowed_intent_types).freeze : nil
        @allowed_agents = allowed_agents ? Array(allowed_agents).map(&:to_sym).freeze : nil
        @allowed_execution_modes = allowed_execution_modes ? Array(allowed_execution_modes).map(&:to_sym).freeze : nil
        @cacheable = !!cacheable
      end

      def read_only?
        @read_only
      end

      def requires_merchant_scope?
        @requires_merchant_scope
      end

      def cacheable?
        @cacheable
      end

      def to_h
        {
          key: @key,
          class_name: @class_name,
          description: @description,
          read_only: @read_only,
          requires_merchant_scope: @requires_merchant_scope,
          allowed_intent_types: @allowed_intent_types,
          allowed_agents: @allowed_agents,
          allowed_execution_modes: @allowed_execution_modes,
          cacheable: @cacheable
        }
      end
    end
  end
end
