# frozen_string_literal: true

module Ai
  module Dev
    # Runs the full AI pipeline and collects safe debug metadata for the dev playground.
    # Does not expose prompts, API keys, or raw internal payloads.
    class PlaygroundRunner
      def self.call(message:, merchant_id:)
        new(message: message, merchant_id: merchant_id).call
      end

      def initialize(message:, merchant_id:)
        @message = message.to_s.strip
        @merchant_id = merchant_id
        @request_id = "playground-#{SecureRandom.hex(8)}"
      end

      def call
        return error_result('Message is required') if @message.blank?
        return error_result('Merchant required') unless @merchant_id.present?

        Thread.current[:ai_request_id] = @request_id
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        result = run_pipeline
        result[:latency_ms] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round
        result[:request_id] = @request_id
        result
      rescue StandardError => e
        {
          error: e.message,
          request_id: @request_id,
          latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round
        }
      end

      private

      def error_result(msg)
        { error: msg, request_id: @request_id }
      end

      def run_pipeline
        # 1. Parsing
        parsed = Ai::Tools::IntentDetector.detect(@message)

        # 2. Orchestration (runs first in real flow)
        run_result = Ai::Orchestration::ConstrainedRunner.call(
          message: @message,
          merchant_id: @merchant_id,
          request_id: @request_id
        )

        if run_result.orchestration_used?
          latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round
          return build_orchestration_result(run_result, parsed, latency)
        end

        # 3. Agent path: Router -> Retrieval -> Agent
        build_agent_path_result(parsed)
      end

      def build_orchestration_result(run_result, parsed)
        agent_key = run_result.step_count > 1 ? 'orchestration' : "tool:#{run_result.tool_names.first}"
        composed = Ai::ResponseComposer.call(
          reply_text: run_result.reply_text,
          citations: [],
          agent_key: agent_key,
          model_used: nil,
          fallback_used: false,
          data: safe_data(run_result.deterministic_data),
          tool_name: run_result.tool_names.first,
          tool_result: run_result.deterministic_data,
          memory_used: false
        )
        audit = write_audit(
          agent_key: composed[:agent_key],
          composition: composed[:composition],
          tool_used: true,
          tool_names: run_result.tool_names.to_a,
          citations_count: 0,
          latency_ms: latency_ms || run_result.metadata[:latency_ms],
          orchestration_used: true,
          orchestration_step_count: run_result.step_count,
          orchestration_halted_reason: run_result.halted_reason
        )
        {
          input: { message: @message },
          parsing: { intent_detected: parsed.present?, tool_name: parsed&.dig(:tool_name), args_keys: parsed&.dig(:args)&.keys },
          routing: { agent: composed[:agent_key], path: run_result.step_count > 1 ? 'orchestration' : 'tool_only' },
          retrieval: { sections_count: 0, citations_count: 0 },
          tools: { tool_names: run_result.tool_names.to_a, step_count: run_result.step_count },
          orchestration: {
            used: true,
            step_count: run_result.step_count,
            tool_names: run_result.tool_names.to_a,
            halted_reason: run_result.halted_reason,
            step_summaries: run_result.step_summaries_for_debug
          },
          memory: { used: false },
          composition: composed[:composition]&.slice(:composition_mode, :used_tool_data, :used_doc_context, :citations_count),
          response: { reply: composed[:reply], citations: [] },
          debug: build_debug_section(composed, nil, latency_ms || run_result.metadata[:latency_ms], nil),
          audit: audit_safe(audit)
        }
      end

      def build_agent_path_result(parsed)
        agent_key = Ai::Router.new(@message).call
        agent_key = Ai::AgentRegistry.default_key unless Ai::AgentRegistry.all_keys.include?(agent_key)
        retriever_result = Ai::Rag::RetrievalService.call(@message, agent_key: agent_key)
        context_text = retriever_result[:context_text]
        citations = retriever_result[:citations] || []
        selected_retriever = retriever_result.dig(:debug, :retriever)

        agent_class = Ai::AgentRegistry.fetch(agent_key)
        agent = build_agent(agent_class, agent_key, context_text, citations)
        result = agent.call
        latency_ms = @started_at ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round : nil

        composed = Ai::ResponseComposer.call(
          reply_text: result.reply_text,
          citations: result.citations,
          agent_key: result.agent_key,
          model_used: result.model_used,
          fallback_used: result.fallback_used,
          data: safe_data(result.data),
          memory_used: false
        )

        memory_result = {}
        chat_session = Merchant.find_by(id: @merchant_id)&.ai_chat_sessions&.order(updated_at: :desc)&.first
        if chat_session
          ctx = Ai::ConversationContextBuilder.call(chat_session, max_turns: Ai::Conversation::MemoryBudgeter.max_recent_messages)
          memory_result = Ai::Conversation::MemoryBudgeter.call(
            summary_text: ctx[:summary_text],
            recent_messages: ctx[:recent_messages],
            user_preferences: ctx[:user_preferences],
            open_tasks_or_followups: ctx[:open_tasks_or_followups],
            current_topic: ctx[:current_topic],
            sanitization_applied: ctx[:summary_text].present?
          )
        end

        audit = write_audit(
          agent_key: composed[:agent_key],
          composition: composed[:composition],
          tool_used: composed.dig(:composition, :used_tool_data),
          tool_names: [],
          citations_count: result.citations.size,
          retrieved_sections_count: retriever_result[:final_sections_count] || retriever_result[:citations]&.size,
          latency_ms: latency_ms,
          retriever_key: selected_retriever,
          memory_used: memory_result[:memory_used],
          summary_used: memory_result[:summary_used]
        )

        {
          input: { message: @message },
          parsing: { intent_detected: parsed.present?, tool_name: parsed&.dig(:tool_name), args_keys: parsed&.dig(:args)&.keys },
          routing: {
            agent: composed[:agent_key],
            path: composed.dig(:composition, :composition_mode) || 'docs_only',
            graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
            vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
          },
          retrieval: {
            retriever: selected_retriever,
            sections_count: retriever_result[:final_sections_count] || citations.size,
            citations_count: citations.size,
            context_chars: context_text&.length,
            context_truncated: retriever_result[:context_truncated],
            citations: citations.map { |c| c.slice(:file, :heading, :anchor).merge(excerpt_preview: (c[:excerpt].to_s[0, 100])) }
          },
          tools: { tool_names: [], step_count: 0 },
          orchestration: { used: false },
          memory: {
            used: memory_result[:memory_used],
            summary_used: memory_result[:summary_used],
            recent_count: memory_result[:recent_messages_count],
            current_topic: memory_result[:current_topic]
          },
          composition: composed[:composition]&.slice(:composition_mode, :used_tool_data, :used_doc_context, :citations_count, :used_memory_context),
          response: { reply: composed[:reply], citations: composed[:citations] },
          debug: build_debug_section(composed, selected_retriever, latency_ms, retriever_result, memory_result),
          audit: audit_safe(audit)
        }
      end

      def build_agent(agent_class, agent_key, context_text, citations)
        if agent_key == :reporting_calculation
          agent_class.new(merchant_id: @merchant_id, message: @message, context_text: context_text, citations: citations)
        else
          agent_class.new(
            message: @message,
            context_text: context_text,
            citations: citations,
            conversation_history: [],
            memory_text: ''
          )
        end
      end

      def build_debug_section(composed, retriever, latency_ms, retriever_result, memory_result = nil)
        h = {
          model_used: composed[:model_used],
          fallback_used: composed[:fallback_used],
          composition_mode: composed.dig(:composition, :composition_mode)
        }
        h[:latency_ms] = latency_ms if latency_ms
        h[:retriever] = retriever if retriever
        h[:retrieved_sections_count] = retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size if retriever_result
        h[:memory_used] = memory_result&.dig(:memory_used) if memory_result
        h[:summary_used] = memory_result&.dig(:summary_used) if memory_result
        h.compact
      end

      def write_audit(**attrs)
        record = Ai::AuditTrail::RecordBuilder.call(
          request_id: @request_id,
          endpoint: 'dev_playground',
          merchant_id: @merchant_id,
          success: true,
          **attrs
        )
        Ai::AuditTrail::Writer.write(record)
        AiRequestAudit.where(request_id: @request_id).last
      end

      def audit_safe(audit)
        return {} unless audit.present?

        audit.attributes.slice(
          'id', 'request_id', 'agent_key', 'retriever_key', 'composition_mode',
          'tool_used', 'tool_names', 'citations_count', 'latency_ms', 'success'
        )
      end

      def safe_data(data)
        return nil if data.blank?

        data.is_a?(Hash) ? data : { _preview: data.to_s[0, 200] }
      end
    end
  end
end
