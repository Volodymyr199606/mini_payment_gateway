# frozen_string_literal: true

module Dashboard
  class AiController < Dashboard::BaseController
    AI_RATE_LIMIT = 20
    AI_RATE_WINDOW = 60

    def show
      # Renders the AI chat page
    end

    def chat
      msg = chat_params[:message].to_s.strip
      if msg.blank?
        return render json: { error: 'message_required' }, status: :unprocessable_entity
      end

      if ai_rate_limited?
        return render json: {
          error: 'rate_limited',
          message: "AI chat limit: #{AI_RATE_LIMIT} requests per #{AI_RATE_WINDOW} seconds."
        }, status: :too_many_requests
      end

      agent_param = chat_params[:agent].to_s.strip
      agent_key = if agent_param.present? && agent_param != "auto"
                    agent_param.to_sym
                  else
                    ::Ai::Router.new(msg).call
                  end
      retriever_result = ::Ai::Rag::DocsRetriever.new(msg, agent_key: agent_key).call
      context_text = retriever_result[:context_text]
      citations = retriever_result[:citations]

      agent_class = agent_class_for(agent_key)
      agent = build_agent(agent_class, agent_key, msg, context_text, citations)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out = agent.call
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      increment_ai_chat_count

      payload = {
        reply: out[:reply],
        agent: agent_key.to_s,
        citations: out[:citations],
        model_used: out[:model_used],
        fallback_used: out[:fallback_used]
      }
      payload[:data] = out[:data] if out[:data].present?

      render json: payload
    end

    private

    def chat_params
      params.permit(:message, :agent)
    end

    def build_agent(agent_class, agent_key, message, context_text, citations)
      if agent_key == :reporting_calculation
        agent_class.new(merchant_id: current_merchant.id, message: message, context_text: context_text, citations: citations)
      else
        agent_class.new(message: message, context_text: context_text, citations: citations)
      end
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
  end
end
