# frozen_string_literal: true

module Dashboard
  class AiController < Dashboard::BaseController
    include ActionController::Live

    AI_RATE_LIMIT = 20
    AI_RATE_WINDOW = 60

    def show
      # Renders the AI chat page
    end

    def reset_chat_session
      current_merchant.ai_chat_sessions.create!
      render json: { ok: true }
    end

    def chat
      msg = parse_message_param.to_s.strip
      if msg.blank?
        return render json: { error: 'message_required', message: 'Message is required' }, status: :bad_request
      end

      if ai_rate_limited?
        return render json: {
          error: 'rate_limited',
          message: "AI chat limit: #{AI_RATE_LIMIT} requests per #{AI_RATE_WINDOW} seconds."
        }, status: :too_many_requests
      end

      Thread.current[:ai_request_id] = request.request_id
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      retriever_result = nil
      out = nil
      agent_key = nil
      selected_retriever = nil
      memory_text = nil
      recent_count = 0

      chat_session = find_or_create_chat_session
      AiChatMessage.create!(
        ai_chat_session: chat_session,
        merchant_id: current_merchant.id,
        role: 'user',
        content: msg
      )

      # Follow-up resolution: resolve inherited context before routing/tools
      ctx = ::Ai::ConversationContextBuilder.call(chat_session, max_turns: ::Ai::Conversation::MemoryBudgeter.max_recent_messages)
      intent_resolution = ::Ai::Followups::IntentResolver.call(
        message: msg,
        recent_messages: ctx[:recent_messages],
        merchant_id: current_merchant.id
      )
      followup_result = intent_resolution[:followup]

      # Constrained orchestration: up to 2 deterministic tool steps when clearly applicable
      run_result = ::Ai::Orchestration::ConstrainedRunner.call(
        message: msg,
        merchant_id: current_merchant.id,
        request_id: request.request_id,
        resolved_intent: intent_resolution[:intent]
      )
      if run_result.orchestration_used?
        latency_ms = run_result.metadata[:latency_ms] || ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        agent_key = run_result.step_count > 1 ? 'orchestration' : "tool:#{run_result.tool_names.first}"
        composed = ::Ai::ResponseComposer.call(
          reply_text: run_result.reply_text,
          citations: [],
          agent_key: agent_key,
          model_used: nil,
          fallback_used: false,
          data: run_result.deterministic_data,
          tool_name: run_result.tool_names.first,
          tool_result: run_result.deterministic_data,
          memory_used: false
        )
        AiChatMessage.create!(
          ai_chat_session: chat_session,
          merchant_id: current_merchant.id,
          role: 'assistant',
          content: composed[:reply],
          agent: composed[:agent_key]
        )
        increment_ai_chat_count
        write_ai_audit(
          request_id: request.request_id,
          endpoint: 'dashboard',
          merchant_id: current_merchant.id,
          agent_key: composed[:agent_key],
          composition: composed[:composition],
          tool_used: true,
          tool_names: run_result.tool_names.to_a,
          citations_count: 0,
          latency_ms: latency_ms,
          success: run_result.success?,
          orchestration_used: true,
          orchestration_step_count: run_result.step_count,
          orchestration_halted_reason: run_result.halted_reason,
          followup_metadata: followup_metadata_safe(followup_result),
          policy_metadata: policy_metadata_from_run(run_result, followup_result)
        )
        payload = build_response_payload(composed)
        payload[:debug] = build_debug_payload_for_orchestration(composed, run_result, latency_ms, followup_result) if ai_debug?
        return render json: payload
      end

      ctx = ::Ai::ConversationContextBuilder.call(chat_session, max_turns: ::Ai::Conversation::MemoryBudgeter.max_recent_messages)
      memory_result = ::Ai::Conversation::MemoryBudgeter.call(
        summary_text: ctx[:summary_text],
        recent_messages: ctx[:recent_messages],
        user_preferences: ctx[:user_preferences],
        open_tasks_or_followups: ctx[:open_tasks_or_followups],
        current_topic: ctx[:current_topic],
        sanitization_applied: ctx[:summary_text].present?
      )
      memory_text = memory_result[:memory_text].to_s
      conversation_history = memory_text.present? ? [] : chat_session.ai_chat_messages.chronological.limit(10).map { |m| { role: m.role, content: m.content } }[0..-2] || []
      recent_count = memory_result[:recent_messages_count]

      agent_param = chat_params[:agent].to_s.strip
      response_style = followup_result[:response_style_adjustments]
      agent_key = if agent_param.present? && agent_param != "auto"
                    agent_param.to_sym
                  else
                    ::Ai::Router.new(msg).call
                  end
      agent_key = ::Ai::AgentRegistry.default_key unless ::Ai::AgentRegistry.all_keys.include?(agent_key)
      retriever_result = ::Ai::Rag::RetrievalService.call(msg, agent_key: agent_key)
      selected_retriever = retriever_result.dig(:debug, :retriever).presence || resolve_retriever_name
      context_text = retriever_result[:context_text]
      citations = retriever_result[:citations]

      agent_class = ::Ai::AgentRegistry.fetch(agent_key)
      agent = build_agent(agent_class, agent_key, msg, context_text, citations,
                         conversation_history: conversation_history,
                         memory_text: memory_text,
                         response_style: response_style)

      if streaming_requested?
        return perform_streaming_chat(
          agent: agent,
          msg: msg,
          agent_key: agent_key,
          retriever_result: retriever_result,
          selected_retriever: selected_retriever,
          memory_result: memory_result,
          recent_count: recent_count,
          chat_session: chat_session,
          started_at: started_at,
          followup_result: followup_result
        )
      end

      out = agent.call
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      composed = ::Ai::ResponseComposer.call(
        reply_text: out.reply_text,
        citations: out.citations,
        agent_key: out.agent_key,
        model_used: out.model_used,
        fallback_used: out.fallback_used,
        data: out.data,
        memory_used: memory_result&.dig(:memory_used)
      )

      AiChatMessage.create!(
        ai_chat_session: chat_session,
        merchant_id: current_merchant.id,
        role: 'assistant',
        content: composed[:reply],
        agent: composed[:agent_key]
      )

      increment_ai_chat_count

      log_ai_request_success(out, msg, agent_key, retriever_result, selected_retriever, latency_ms, memory_result, recent_count)

      write_ai_audit(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        agent_key: out.agent_key,
        retriever_key: selected_retriever,
        composition: composed[:composition],
        tool_used: composed.dig(:composition, :used_tool_data),
        tool_names: [],
        fallback_used: out.fallback_used,
        citation_reask_used: out.metadata[:guardrail_reask],
        memory_used: memory_result&.dig(:memory_used),
        summary_used: memory_result&.dig(:summary_used),
        citations_count: out.citations.size,
        retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
        latency_ms: latency_ms,
        model_used: out.model_used,
        success: true,
        followup_metadata: followup_metadata_safe(followup_result)
      )

      payload = build_response_payload(composed)
      payload[:debug] = build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms, memory_result, composed, followup_result) if ai_debug?

      render json: payload
    rescue StandardError => e
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      log_ai_request_error(e, msg, agent_key, retriever_result, selected_retriever, latency_ms)
      write_ai_audit(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        agent_key: agent_key&.to_s,
        retriever_key: selected_retriever,
        citations_count: retriever_result&.dig(:citations)&.size,
        retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
        latency_ms: latency_ms,
        success: false,
        error_class: e.class.name,
        error_message: e.message
      )
      raise
    end

    private

    def chat_params
      params.permit(:message, :agent, :stream)
    end

    def streaming_requested?
      return false unless streaming_enabled?
      stream_val = chat_params[:stream]
      stream_val = parse_stream_from_body if stream_val.blank? && request.content_type.to_s.include?('application/json')
      ActiveModel::Type::Boolean.new.cast(stream_val)
    end

    def streaming_enabled?
      ENV['AI_STREAMING_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
    end

    def parse_stream_from_body
      return nil unless request.content_type.to_s.include?('application/json')
      parsed = JSON.parse(request.raw_post) rescue {}
      parsed['stream'] || parsed[:stream]
    end

    def perform_streaming_chat(agent:, msg:, agent_key:, retriever_result:, selected_retriever:, memory_result:, recent_count:, chat_session:, started_at:, followup_result: nil)
      response.headers['Content-Type'] = 'text/event-stream'
      response.headers['Cache-Control'] = 'no-cache'
      response.headers['X-Accel-Buffering'] = 'no'

      pipeline_context = { context_text: retriever_result[:context_text], citations: retriever_result[:citations] }
      messages = agent.messages_for_llm

      pre = ::Ai::Guardrails::Pipeline.call(
        input: { built_messages: messages },
        result: nil,
        context: pipeline_context
      )

      if pre[:short_circuit]
        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        out = agent.build_result_from_pipeline(pre)
        composed = ::Ai::ResponseComposer.call(
          reply_text: out.reply_text,
          citations: out.citations,
          agent_key: out.agent_key,
          model_used: out.model_used,
          fallback_used: out.fallback_used,
          memory_used: memory_result&.dig(:memory_used)
        )
        write_sse_chunk(response.stream, composed[:reply]) if composed[:reply].present?
        finalize_streaming(chat_session, composed, out, agent_key, retriever_result, selected_retriever, memory_result, recent_count, latency_ms, msg, followup_result)
        return
      end

      streamer = ::Ai::Streaming::ResponseStreamer.new
      client = ::Ai::Generation::StreamingClient.new

      raw = client.stream(messages: messages, temperature: 0.3, max_tokens: 1024) do |chunk|
        streamer << chunk
        write_sse_chunk(response.stream, chunk)
      end

      content = raw[:content].to_s.strip

      if content.blank? && raw[:error].present?
        raw = agent.send(:groq_client).chat(messages: messages, temperature: 0.3, max_tokens: 1024)
        content = raw[:content].to_s.strip
        content = "I couldn't generate a reply." if content.blank?
        write_sse_chunk(response.stream, content)
      elsif content.blank?
        content = agent.fallback_message
        write_sse_chunk(response.stream, content)
      end

      content = agent.send(:strip_inline_citations, agent.send(:strip_filler_phrases, content))
      post = ::Ai::Guardrails::Pipeline.call(
        input: { built_messages: messages },
        result: { content: content, model_used: raw[:model_used], fallback_used: raw[:fallback_used] },
        context: pipeline_context
      )

      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      out = agent.build_result_from_pipeline(post)
      composed = ::Ai::ResponseComposer.call(
        reply_text: out.reply_text,
        citations: out.citations,
        agent_key: out.agent_key,
        model_used: out.model_used,
        fallback_used: out.fallback_used,
        memory_used: memory_result&.dig(:memory_used)
      )

      AiChatMessage.create!(
        ai_chat_session: chat_session,
        merchant_id: current_merchant.id,
        role: 'assistant',
        content: composed[:reply],
        agent: composed[:agent_key]
      )
      increment_ai_chat_count
      log_ai_request_success(out, msg, agent_key, retriever_result, selected_retriever, latency_ms, memory_result, recent_count)
      write_ai_audit(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        agent_key: out.agent_key,
        retriever_key: selected_retriever,
        composition: composed[:composition],
        tool_used: false,
        tool_names: [],
        fallback_used: out.fallback_used,
        citation_reask_used: out.metadata[:guardrail_reask],
        memory_used: memory_result&.dig(:memory_used),
        summary_used: memory_result&.dig(:summary_used),
        citations_count: out.citations.size,
        retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
        latency_ms: latency_ms,
        model_used: out.model_used,
        success: true,
        followup_metadata: followup_metadata_safe(followup_result)
      )

      payload = build_response_payload(composed)
      payload[:debug] = build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms, memory_result, composed, followup_result) if ai_debug?
      write_sse_done(response.stream, payload)
    rescue StandardError => e
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      log_ai_request_error(e, msg, agent_key, retriever_result, selected_retriever, latency_ms)
      write_ai_audit(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        agent_key: agent_key&.to_s,
        retriever_key: selected_retriever,
        citations_count: retriever_result&.dig(:citations)&.size,
        retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
        latency_ms: latency_ms,
        success: false,
        error_class: e.class.name,
        error_message: e.message
      )
      write_sse_error(response.stream, e.message)
    ensure
      response.stream.close
    end

    def finalize_streaming(chat_session, composed, out, agent_key, retriever_result, selected_retriever, memory_result, recent_count, latency_ms, msg, followup_result = nil)
      AiChatMessage.create!(
        ai_chat_session: chat_session,
        merchant_id: current_merchant.id,
        role: 'assistant',
        content: composed[:reply],
        agent: composed[:agent_key]
      )
      increment_ai_chat_count
      log_ai_request_success(out, msg, agent_key, retriever_result, selected_retriever, latency_ms, memory_result, recent_count)
      write_ai_audit(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        agent_key: out.agent_key,
        retriever_key: selected_retriever,
        composition: composed[:composition],
        tool_used: false,
        tool_names: [],
        fallback_used: out.fallback_used,
        citation_reask_used: out.metadata[:guardrail_reask],
        memory_used: memory_result&.dig(:memory_used),
        summary_used: memory_result&.dig(:summary_used),
        citations_count: out.citations.size,
        retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
        latency_ms: latency_ms,
        model_used: out.model_used,
        success: true,
        followup_metadata: followup_metadata_safe(followup_result)
      )
      payload = build_response_payload(composed)
      payload[:debug] = build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms, memory_result, composed, followup_result) if ai_debug?
      write_sse_done(response.stream, payload)
    end

    def write_sse_chunk(stream, text)
      return if text.to_s.empty?
      stream.write("event: chunk\ndata: {\"delta\":#{text.to_json}}\n\n")
    end

    def write_sse_done(stream, payload)
      stream.write("event: done\ndata: #{payload.to_json}\n\n")
    end

    def write_sse_error(stream, message)
      stream.write("event: error\ndata: {\"error\":#{message.to_json}}\n\n")
    end

    # Accept JSON body { message: "..." } or form-encoded message param.
    def parse_message_param
      return chat_params[:message] if params.key?(:message) || params.key?("message")
      return nil unless request.content_type.to_s.include?("application/json")

      parsed = JSON.parse(request.raw_post)
      parsed["message"] || parsed[:message]
    rescue JSON::ParserError
      nil
    end

    def build_agent(agent_class, agent_key, message, context_text, citations, conversation_history: [], memory_text: '', response_style: nil)
      if agent_key == :reporting_calculation
        agent_class.new(merchant_id: current_merchant.id, message: message, context_text: context_text, citations: citations)
      else
        agent_class.new(
          message: message,
          context_text: context_text,
          citations: citations,
          conversation_history: conversation_history,
          memory_text: memory_text,
          response_style: response_style
        )
      end
    end

    def followup_metadata_safe(followup)
      return nil unless followup.is_a?(Hash) && followup[:followup_detected]

      {
        followup_detected: true,
        followup_type: followup[:followup_type].to_s.strip.presence,
        inherited_context_summary: inherited_context_summary_safe(followup)
      }
    end

    def inherited_context_summary_safe(followup)
      return nil unless followup.is_a?(Hash)

      parts = []
      parts << "entities:#{followup[:inherited_entities]&.keys&.join(',')}" if followup[:inherited_entities]&.any?
      parts << "time_range" if followup[:inherited_time_range].present?
      parts << "topic:#{followup[:inherited_topic]}" if followup[:inherited_topic].present?
      parts.any? ? parts.join('; ') : nil
    end

    def ai_rate_limited?
      key = "ai_chat:merchant:#{current_merchant.id}"
      count = (Rails.cache.read(key) || 0).to_i
      count >= AI_RATE_LIMIT
    end

    def increment_ai_chat_count
      key = "ai_chat:merchant:#{current_merchant.id}"
      count = (Rails.cache.read(key) || 0).to_i
      Rails.cache.write(key, count + 1, expires_in: AI_RATE_WINDOW.seconds)
    end

    # Find the most recent chat session for the current merchant, or create one (scoped to merchant).
    def find_or_create_chat_session
      current_merchant.ai_chat_sessions.order(updated_at: :desc).first ||
        current_merchant.ai_chat_sessions.create!
    end

    def ai_debug?
      ::Ai::Observability::EventLogger.ai_debug_enabled?
    end

    def resolve_retriever_name
      graph = ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
      vector = ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1])
      graph ? 'GraphExpandedRetriever' : (vector ? 'HybridRetriever' : 'DocsRetriever')
    end

    def log_ai_request_success(out, msg, agent_key, retriever_result, selected_retriever, latency_ms, memory_result, recent_count)
      ::Ai::Observability::EventLogger.log_ai_request(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        question: msg,
        selected_agent: out.agent_key,
        selected_retriever: selected_retriever,
        graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        memory_used: memory_result&.dig(:memory_used),
        summary_used: memory_result&.dig(:summary_used),
        recent_messages_count: recent_count,
        retrieved_sections_count: out.citations.size,
        citations_count: out.citations.size,
        fallback_used: out.fallback_used,
        citation_reask_used: out.metadata[:guardrail_reask],
        model_used: out.model_used,
        latency_ms: latency_ms,
        success: true
      )
    end

    def log_ai_request_error(e, msg, agent_key, retriever_result, selected_retriever, latency_ms)
      ::Ai::Observability::EventLogger.log_ai_request(
        request_id: request.request_id,
        endpoint: 'dashboard',
        merchant_id: current_merchant&.id,
        question: msg,
        selected_agent: agent_key&.to_s,
        selected_retriever: selected_retriever,
        graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        memory_used: nil,
        summary_used: nil,
        recent_messages_count: nil,
        retrieved_sections_count: retriever_result&.dig(:citations)&.size,
        citations_count: retriever_result&.dig(:citations)&.size,
        fallback_used: nil,
        citation_reask_used: nil,
        model_used: nil,
        latency_ms: latency_ms,
        success: false,
        error_class: e.class.name,
        error_message: e.message
      )
    end

    def build_response_payload(composed)
      payload = {
        reply: composed[:reply],
        agent: composed[:agent_key],
        citations: composed[:citations],
        model_used: composed[:model_used],
        fallback_used: composed[:fallback_used]
      }
      payload[:data] = composed[:data] if composed[:data].present?
      payload
    end

    def build_debug_payload_for_tool(composed, tool_name, latency_ms)
      merge_composition_debug(
        { tool_used: tool_name, latency_ms: latency_ms },
        composed[:composition]
      )
    end

    def build_debug_payload_for_orchestration(composed, run_result, latency_ms, followup = nil)
      debug = merge_composition_debug(
        {
          tool_used: run_result.tool_names.join(','),
          latency_ms: latency_ms,
          orchestration_used: true,
          orchestration_step_count: run_result.step_count,
          orchestration_tool_names: run_result.tool_names.to_a,
          orchestration_halted_reason: run_result.halted_reason,
          orchestration_step_summaries: run_result.step_summaries_for_debug
        }.compact,
        composed[:composition]
      )
      debug.merge!(followup_debug_safe(followup))
      debug.merge!(policy_debug_from_run(run_result, followup))
    end

    def policy_metadata_from_run(run_result, followup_result)
      meta = run_result&.metadata || {}
      followup = followup_result.is_a?(Hash) ? followup_result : {}
      {
        authorization_denied: !!meta[:authorization_denied],
        tool_blocked_by_policy: !!meta[:tool_blocked_by_policy],
        followup_inheritance_blocked: !!followup[:followup_inheritance_blocked],
        policy_reason_code: meta[:authorization_denied] ? 'access_denied' : nil
      }.compact
    end

    def policy_debug_from_run(run_result, followup = nil)
      meta = run_result&.metadata || {}
      followup_hash = followup.is_a?(Hash) ? followup : {}
      {
        authorization_checked: true,
        authorization_denied: !!meta[:authorization_denied],
        denied_reason_code: meta[:authorization_denied] ? 'access_denied' : nil,
        tool_blocked_by_policy: !!meta[:tool_blocked_by_policy],
        followup_inheritance_blocked: !!followup_hash[:followup_inheritance_blocked]
      }.compact
    end

    def write_ai_audit(**attrs)
      record = ::Ai::AuditTrail::RecordBuilder.call(**attrs)
      ::Ai::AuditTrail::Writer.write(record)
    end

    def merge_composition_debug(debug, composition)
      return debug unless composition.is_a?(Hash)

      extra = {
        composition_mode: composition[:composition_mode],
        used_tool_data: composition[:used_tool_data],
        used_doc_context: composition[:used_doc_context],
        used_memory_context: composition[:used_memory_context],
        citations_count: composition[:citations_count],
        deterministic_fields_used: composition[:deterministic_fields_used]
      }.compact
      debug.merge(extra)
    end

    def build_debug_payload(out, agent_key, selected_retriever, retriever_result, latency_ms, memory_result, composed = nil, followup = nil)
      debug = ::Ai::Observability::EventLogger.build_debug_payload(
        selected_agent: out.agent_key,
        selected_retriever: selected_retriever,
        graph_enabled: ENV['AI_CONTEXT_GRAPH_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        vector_enabled: ENV['AI_VECTOR_RAG_ENABLED'].to_s.strip.downcase.in?(%w[true 1]),
        retrieved_sections_count: retriever_result&.dig(:final_sections_count) || retriever_result&.dig(:citations)&.size,
        citations_count: out.citations.size,
        fallback_used: out.fallback_used,
        citation_reask_used: out.metadata[:guardrail_reask],
        model_used: out.model_used,
        memory_used: memory_result&.dig(:memory_used),
        summary_used: memory_result&.dig(:summary_used),
        latency_ms: latency_ms,
        retriever_debug: retriever_result&.dig(:debug)
      )
      retriever_debug = retriever_result&.dig(:debug)
      debug.merge!(retriever_debug.symbolize_keys) if retriever_debug.is_a?(Hash) && retriever_debug.present?
      # Prefer top-level retrieval fields; retriever_debug (merged above) supplies when stubbed
      debug[:context_truncated] = retriever_result[:context_truncated] if retriever_result&.key?(:context_truncated)
      debug[:final_context_chars] = retriever_result[:final_context_chars] if retriever_result&.key?(:final_context_chars)
      debug[:final_sections_count] = retriever_result[:final_sections_count] if retriever_result&.key?(:final_sections_count)
      debug[:memory_truncated] = memory_result[:memory_truncated] if memory_result&.key?(:memory_truncated)
      debug[:final_memory_chars] = memory_result[:final_memory_chars] if memory_result
      debug[:recent_messages_count] = memory_result[:recent_messages_count] if memory_result
      debug[:summary_updated] = memory_result[:summary_updated] if memory_result
      debug[:summary_chars] = memory_result[:summary_chars] if memory_result
      debug[:current_topic] = memory_result[:current_topic] if memory_result
      debug[:sanitization_applied] = memory_result[:sanitization_applied] if memory_result
      debug.merge!(followup_debug_safe(followup))
      merge_composition_debug(debug, composed&.dig(:composition))
    end

    def followup_debug_safe(followup)
      return {} unless followup.is_a?(Hash) && followup[:followup_detected]

      {
        followup_detected: true,
        followup_type: followup[:followup_type],
        inherited_entities: followup[:inherited_entities]&.keys,
        inherited_time_range: followup[:inherited_time_range].present?,
        inherited_topic: followup[:inherited_topic],
        response_style_adjustments: followup[:response_style_adjustments]
      }.compact
    end
  end
end
