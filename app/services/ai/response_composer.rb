# frozen_string_literal: true

module Ai
  # Source-aware response composition. Assembles final response payload with explicit
  # provenance. Deterministic data is clearly separated from doc citations.
  # Do not fabricate citations for tool data.
  class ResponseComposer
    COMPOSITION_MODES = %w[tool_only docs_only memory_docs hybrid_tool_docs memory_tool_docs].freeze

    def self.call(**inputs)
      new(**inputs).call
    end

    def initialize(
      reply_text: '',
      citations: [],
      agent_key: nil,
      model_used: nil,
      fallback_used: false,
      data: nil,
      tool_name: nil,
      tool_result: nil,
      memory_used: false
    )
      @reply_text = reply_text.to_s
      @citations = citations.to_a
      @agent_key = agent_key.to_s
      @model_used = model_used
      @fallback_used = !!fallback_used
      @data = data
      @tool_name = tool_name.to_s.strip.presence
      @tool_result = tool_result
      @memory_used = !!memory_used
    end

    def call
      composition = build_composition
      {
        reply: @reply_text,
        citations: doc_only_citations,
        agent_key: @agent_key,
        model_used: @model_used,
        fallback_used: @fallback_used,
        data: @data,
        composition: composition
      }
    end

    private

    def build_composition
      used_tool = used_tool_data?
      used_doc = used_doc_context?
      used_mem = @memory_used

      mode = resolve_mode(used_tool, used_doc, used_mem)
      deterministic_fields = safe_deterministic_fields(used_tool)

      {
        used_tool_data: used_tool,
        used_doc_context: used_doc,
        used_memory_context: used_mem,
        citations_count: @citations.size,
        deterministic_fields_used: deterministic_fields,
        composition_mode: mode
      }
    end

    def used_tool_data?
      @tool_name.present? || deterministic_agent?
    end

    def deterministic_agent?
      @agent_key == 'reporting_calculation'
    end

    def used_doc_context?
      @citations.present?
    end

    def doc_only_citations
      # Citations are doc-only; never fabricate for tool data.
      # When tool-only, citations stay empty.
      @citations
    end

    def resolve_mode(used_tool, used_doc, used_mem)
      if used_tool && used_doc
        used_mem ? 'memory_tool_docs' : 'hybrid_tool_docs'
      elsif used_tool
        'tool_only'
      elsif used_mem && used_doc
        'memory_docs'
      elsif used_doc
        'docs_only'
      elsif used_mem
        'memory_docs'  # docs can be empty but memory used
      else
        'docs_only'    # fallback when no sources
      end
    end

    def safe_deterministic_fields(used_tool)
      return [] unless used_tool

      if @tool_name.present?
        [@tool_name.sub(/\Aget_/, '')]
      elsif deterministic_agent?
        ['ledger_summary']
      else
        []
      end
    end
  end
end
