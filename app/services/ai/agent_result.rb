# frozen_string_literal: true

module Ai
  # Standardized result from any AI agent. All agents return this contract.
  AgentResult = Struct.new(
    :reply_text,
    :citations,
    :agent_key,
    :model_used,
    :fallback_used,
    :metadata,
    :data,
    keyword_init: true
  ) do
    # Default metadata keys: retriever, docs_used_count, summary_used, guardrail_reask
    def self.default_metadata
      {
        retriever: nil,
        docs_used_count: 0,
        summary_used: false,
        guardrail_reask: false
      }.freeze
    end

    def initialize(reply_text: '', citations: [], agent_key: '', model_used: nil, fallback_used: false, metadata: nil, data: nil)
      meta = self.class.default_metadata.dup
      meta.update(metadata.to_h.transform_keys(&:to_sym)) if metadata.present?
      super(
        reply_text: reply_text.to_s,
        citations: citations.to_a,
        agent_key: agent_key.to_s,
        model_used: model_used,
        fallback_used: !!fallback_used,
        metadata: meta,
        data: data
      )
    end
  end
end
