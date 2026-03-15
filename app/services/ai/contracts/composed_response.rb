# frozen_string_literal: true

module Ai
  module Contracts
    # Contract for response composition output (ResponseComposer).
    # Stable keys: reply, citations, agent_key, model_used, fallback_used, data, composition.
    class ComposedResponse
      attr_reader :reply, :citations, :agent_key, :model_used, :fallback_used,
                  :data, :composition, :contract_version

      def initialize(
        reply: '',
        citations: [],
        agent_key: '',
        model_used: nil,
        fallback_used: false,
        data: nil,
        composition: {},
        contract_version: nil
      )
        @reply = reply.to_s
        @citations = citations.is_a?(Array) ? citations : []
        @agent_key = agent_key.to_s.strip.presence || ''
        @model_used = model_used.to_s.strip.presence
        @fallback_used = !!fallback_used
        @data = data
        @composition = composition.is_a?(Hash) ? composition : {}
        @contract_version = contract_version || Contracts::COMPOSED_RESPONSE_VERSION
      end

      def self.from_h(h)
        return nil if h.blank? || !h.is_a?(Hash)

        sym = h.with_indifferent_access
        comp = sym[:composition].to_h.merge(contract_version: sym[:contract_version] || Contracts::COMPOSED_RESPONSE_VERSION)
        new(
          reply: sym[:reply].to_s,
          citations: sym[:citations].to_a,
          agent_key: sym[:agent_key].to_s,
          model_used: sym[:model_used],
          fallback_used: !!sym[:fallback_used],
          data: sym[:data],
          composition: comp,
          contract_version: sym[:contract_version].presence
        )
      end

      def to_h
        {
          reply: @reply,
          citations: @citations,
          agent_key: @agent_key,
          model_used: @model_used,
          fallback_used: @fallback_used,
          data: @data,
          composition: @composition.merge(contract_version: @contract_version),
          contract_version: @contract_version
        }
      end
    end
  end
end
