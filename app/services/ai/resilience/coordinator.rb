# frozen_string_literal: true

module Ai
  module Resilience
    # Central resilience coordinator. Observes failures, chooses fallback mode, returns safe response.
    # Does not retry autonomously; caller may retry when retry_allowed.
    class Coordinator
      FAILURE_STAGES = %i[generation retrieval tool orchestration memory streaming audit_debug unknown].freeze
      FALLBACK_MODES = %i[normal tool_only docs_only tool_plus_docs no_memory no_orchestration non_streaming_fallback safe_failure_message].freeze

      SAFE_MESSAGES = {
        generation: "I'm having trouble generating a reply right now. Please try again in a moment.",
        retrieval: "I couldn't load the docs right now. Please try again shortly.",
        tool: "I couldn't fetch that data right now. Please try again or check the Dashboard.",
        orchestration: "I couldn't complete that request. Please try a simpler question.",
        memory: "Continuing without prior context. Please rephrase if needed.",
        streaming: "Response completed. Please check the full reply below.",
        audit_debug: nil, # Never show user-facing message for audit/debug failure
        unknown: "Something went wrong. Please try again."
      }.freeze

      class << self
        # Infer failure_stage from exception.
        def infer_stage(exception)
          return :unknown unless exception
          msg = exception.message.to_s.downcase
          class_name = exception.class.name.to_s
          return :generation if class_name.include?('Groq') || class_name.include?('Faraday') || msg.include?('groq') || msg.include?('api') && msg.include?('error')
          return :retrieval if msg.include?('retriev') || msg.include?('doc') && msg.include?('fail')
          return :tool if msg.include?('tool') || msg.include?('executor')
          return :orchestration if msg.include?('orchestrat')
          return :streaming if msg.include?('stream') || msg.include?('sse')
          return :audit_debug if msg.include?('audit') || msg.include?('log') || msg.include?('event')
          :unknown
        end

        # Plan fallback decision from failure stage and context.
        def plan_fallback(failure_stage:, context: {})
          stage = failure_stage.to_s.to_sym
          stage = :unknown unless FAILURE_STAGES.include?(stage)

          fallback_mode = choose_fallback_mode(stage, context)
          safe_message = safe_message_for(stage)

          Decision.degrade(
            failure_stage: stage,
            fallback_mode: fallback_mode,
            safe_message: safe_message,
            metadata: { original_path: context[:original_path], has_tool_data: !!context[:tool_data] },
            retry_allowed: retry_allowed?(stage)
          )
        end

        # Build a response hash suitable for build_response_payload / ResponseComposer.
        # When context has tool_data from a prior successful step, use it (deterministic truth preferred).
        def build_safe_response(decision:, context: {})
          reply = decision.safe_message.presence || SAFE_MESSAGES[:unknown]
          data = nil
          mode = 'safe_failure_message'
          used_tool = false

          if context[:tool_data].present? && decision.fallback_mode == :tool_only
            formatted = format_tool_data(context[:tool_data], context[:tool_name])
            reply = formatted.presence || reply
            data = context[:tool_data]
            mode = 'tool_only'
            used_tool = true
          end

          {
            reply: reply,
            agent_key: 'resilience_fallback',
            citations: [],
            data: data,
            model_used: nil,
            fallback_used: true,
            composition: {
              composition_mode: mode,
              used_tool_data: used_tool,
              used_doc_context: false,
              used_memory_context: false
            }
          }
        end

        # Wrap a block; on exception, return safe response instead of raising.
        def with_resilience(context: {}, &block)
          block.call
        rescue StandardError => e
          stage = infer_stage(e)
          decision = plan_fallback(failure_stage: stage, context: context.merge(error_class: e.class.name))
          safe = build_safe_response(decision: decision, context: context)
          { success: false, resilience: decision, safe_response: safe, error: e }
        end

        def safe_message_for(stage)
          SAFE_MESSAGES[stage.to_s.to_sym] || SAFE_MESSAGES[:unknown]
        end

        private

        def choose_fallback_mode(stage, context)
          case stage
          when :generation
            context[:tool_data].present? ? :tool_only : :safe_failure_message
          when :retrieval
            context[:tool_data].present? ? :tool_only : :safe_failure_message
          when :tool
            context[:context_text].present? ? :docs_only : :safe_failure_message
          when :orchestration
            :no_orchestration
          when :memory
            :no_memory
          when :streaming
            :non_streaming_fallback
          when :audit_debug
            :normal
          else
            :safe_failure_message
          end
        end

        def retry_allowed?(stage)
          %i[generation streaming].include?(stage)
        end

        def format_tool_data(data, tool_name)
          return nil unless data.is_a?(Hash)
          # Simple deterministic summary for resilience fallback
          case tool_name.to_s
          when 'get_ledger_summary'
            totals = data['totals'] || data[:totals] || {}
            "Ledger summary: charges, refunds, and fees for the requested period. Check Dashboard for details."
          when 'get_merchant_account'
            "Account summary available. Check Dashboard for full details."
          else
            "Data retrieved. Check Dashboard for details."
          end
        end
      end
    end
  end
end
