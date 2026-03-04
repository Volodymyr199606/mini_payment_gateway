# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ChatController < Api::V1::BaseController
        AI_RATE_LIMIT = 20
        AI_RATE_WINDOW = 60

        def create
          if ai_rate_limited?
            return render_error(
              code: 'rate_limited',
              message: "AI chat limit: #{AI_RATE_LIMIT} requests per #{AI_RATE_WINDOW} seconds.",
              status: :too_many_requests
            )
          end

          message = chat_params[:message].to_s.strip
          if message.blank?
            return render_error(
              code: 'validation_error',
              message: 'message is required',
              status: :bad_request
            )
          end

          agent_key = ::Ai::Router.new(message).call
          retriever_result = ::Ai::Rag::RetrievalService.call(message, agent_key: agent_key)
          context_text = retriever_result[:context_text]
          citations = retriever_result[:citations]

          agent_class = agent_class_for(agent_key)
          agent = build_agent(agent_class, agent_key, message, context_text, citations)

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          out = agent.call
          latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

          increment_ai_chat_count

          log_ai_chat(
            merchant_id: current_merchant.id,
            agent: agent_key.to_s,
            citations: out[:citations].map { |c| c.slice(:file, :heading) },
            model_used: out[:model_used],
            latency_ms: latency_ms,
            fallback_used: out[:fallback_used]
          )

          payload = {
            reply: out[:reply],
            agent: agent_key.to_s,
            citations: out[:citations]
          }
          payload[:data] = out[:data] if out[:data].present?
          render json: payload
        end

        private

        def build_agent(agent_class, agent_key, message, context_text, citations)
          if agent_key == :reporting_calculation
            agent_class.new(merchant_id: current_merchant.id, message: message, context_text: context_text, citations: citations)
          else
            agent_class.new(message: message, context_text: context_text, citations: citations)
          end
        end

        def chat_params
          params.permit(:message)
        end

        def agent_class_for(key)
          case key
          when :support_faq then ::Ai::Agents::SupportFaqAgent
          when :security_compliance then ::Ai::Agents::SecurityAgent
          when :developer_onboarding then ::Ai::Agents::OnboardingAgent
          when :operational then ::Ai::Agents::OperationalAgent
          when :reconciliation_analyst then ::Ai::Agents::ReconciliationAgent
          when :reporting_calculation then ::Ai::Agents::ReportingCalculationAgent
          else ::Ai::Agents::SupportFaqAgent
          end
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

        def log_ai_chat(merchant_id:, agent:, citations:, model_used:, latency_ms:, fallback_used:)
          log_info(
            event: 'ai_chat',
            merchant_id: merchant_id,
            agent: agent,
            citations: citations,
            model_used: model_used,
            latency_ms: latency_ms,
            fallback_used: fallback_used
          )
        end
      end
    end
  end
end
