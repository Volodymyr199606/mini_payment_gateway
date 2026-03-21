# frozen_string_literal: true

module Ai
  module Skills
    # Metadata for a registered skill. Used by Registry and audit surfaces.
    class SkillDefinition
      DEPENDENCY_KEYS = %i[retrieval tools memory context].freeze

      attr_reader :key, :class_name, :description, :deterministic, :dependencies,
                  :input_contract, :output_contract

      def initialize(
        key:,
        class_name:,
        description: '',
        deterministic: true,
        dependencies: [],
        input_contract: '',
        output_contract: ''
      )
        @key = key.to_sym
        @class_name = class_name.to_s
        @description = description.to_s
        @deterministic = !!deterministic
        @dependencies = Array(dependencies).map(&:to_sym).freeze
        @input_contract = input_contract.to_s
        @output_contract = output_contract.to_s

        unknown = @dependencies - DEPENDENCY_KEYS
        raise ArgumentError, "SkillDefinition #{@key}: unknown dependencies #{unknown.inspect}" if unknown.any?
      end

      def deterministic?
        @deterministic
      end

      def mixed?
        !@deterministic
      end

      def depends_on_retrieval?
        @dependencies.include?(:retrieval)
      end

      def depends_on_tools?
        @dependencies.include?(:tools)
      end

      def depends_on_memory?
        @dependencies.include?(:memory)
      end

      def depends_on_context?
        @dependencies.include?(:context)
      end

      def to_h
        {
          key: @key,
          class_name: @class_name,
          description: @description,
          deterministic: @deterministic,
          dependencies: @dependencies,
          input_contract: @input_contract,
          output_contract: @output_contract
        }
      end
    end
  end
end
