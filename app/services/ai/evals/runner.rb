# frozen_string_literal: true

module Ai
  module Evals
    # Runs golden questions through router + retrieval + agent. Used by RSpec for CI eval.
    # Caller must stub GroqClient (non-reporting) and Reporting::LedgerSummary (reporting) for deterministic runs.
    class Runner
      GOLDEN_PATH = Rails.root.join('spec/ai/golden_questions.yml')
      STUB_REPLY = 'Eval stub reply. No secrets here.'

      AGENT_CLASSES = {
        support_faq: Agents::SupportFaqAgent,
        security_compliance: Agents::SecurityAgent,
        developer_onboarding: Agents::OnboardingAgent,
        operational: Agents::OperationalAgent,
        reconciliation_analyst: Agents::ReconciliationAgent,
        reporting_calculation: Agents::ReportingCalculationAgent
      }.freeze

      # Map agent_name (result.agent_key) to router key for golden eval comparison
      AGENT_NAME_TO_ROUTER_KEY = {
        'support_faq' => :support_faq,
        'security' => :security_compliance,
        'onboarding' => :developer_onboarding,
        'operational' => :operational,
        'reconciliation' => :reconciliation_analyst,
        'reporting_calculation' => :reporting_calculation
      }.freeze

      class << self
        def load_questions(path = GOLDEN_PATH)
          return {} unless path.exist?

          YAML.load_file(path).to_h.transform_keys(&:to_sym)
        end

        # Runs all golden questions. Returns array of { agent_key:, question:, result:, errors: [] }.
        # merchant_id: required for reporting agent. Caller should stub GroqClient and LedgerSummary.
        def run_all(merchant_id:, stub_llm: true)
          questions_by_agent = load_questions
          runs = []
          questions_by_agent.each do |expected_agent_key, questions|
            Array(questions).each do |question|
              run = run_one(
                question.to_s.strip,
                merchant_id: merchant_id,
                expected_agent_key: expected_agent_key,
                stub_llm: stub_llm
              )
              runs << run
            end
          end
          runs
        end

        # Runs one question: router -> retrieval -> agent. Returns { agent_key:, question:, result:, errors: [] }.
        def run_one(question, merchant_id:, expected_agent_key: nil, stub_llm: true)
          agent_key = ::Ai::Router.new(question).call
          retriever_result = ::Ai::Rag::RetrievalService.call(question, agent_key: agent_key)
          context_text = retriever_result[:context_text]
          citations = retriever_result[:citations] || []
          had_sections = citations.size >= 1

          agent_class = AGENT_CLASSES[agent_key] || ::Ai::Agents::SupportFaqAgent
          agent = build_agent(agent_class, agent_key, question, context_text, citations, merchant_id: merchant_id)
          result = agent.call

          errors = assert_result(result, agent_key, had_sections: had_sections, expected_agent_key: expected_agent_key)
          {
            agent_key: agent_key,
            question: question,
            result: result,
            errors: errors
          }
        end

        def build_agent(agent_class, agent_key, message, context_text, citations, merchant_id: nil)
          if agent_key == :reporting_calculation
            agent_class.new(
              merchant_id: merchant_id,
              message: message,
              context_text: context_text,
              citations: citations
            )
          else
            agent_class.new(
              message: message,
              context_text: context_text,
              citations: citations,
              conversation_history: [],
              memory_text: ''
            )
          end
        end

        # Returns array of error strings (empty if all assertions pass).
        def assert_result(result, agent_key, had_sections:, expected_agent_key: nil)
          errors = []

          unless result.is_a?(::Ai::AgentResult)
            errors << "expected AgentResult, got #{result.class}"
            return errors
          end

          if expected_agent_key
            actual_router_key = AGENT_NAME_TO_ROUTER_KEY[result.agent_key.to_s] || result.agent_key.to_sym
            if actual_router_key.to_sym != expected_agent_key.to_sym
              errors << "expected agent_key=#{expected_agent_key}, got #{result.agent_key}"
            end
          end

          if had_sections && result.citations.to_a.size < 1
            errors << "retrieval had sections but result has 0 citations"
          end

          if agent_key == :reporting_calculation
            data = result.data
            unless data.is_a?(Hash) && data[:totals].is_a?(Hash)
              errors << "reporting agent must return data with totals hash"
            else
              t = data[:totals]
              %i[charges_cents refunds_cents fees_cents net_cents].each do |k|
                errors << "reporting data.totals missing :#{k}" unless t.key?(k)
              end
              if t.key?(:charges_cents) && t.key?(:refunds_cents) && t.key?(:fees_cents) && t.key?(:net_cents)
                expected_net = t[:charges_cents].to_i - t[:refunds_cents].to_i - t[:fees_cents].to_i
                unless t[:net_cents] == expected_net
                  errors << "reporting net_cents=#{t[:net_cents]} but charges - refunds - fees = #{expected_net}"
                end
              end
            end
          end

          unless secrets_ok?(result.reply_text.to_s)
            errors << "reply_text contains secrets pattern"
          end
          result.citations.to_a.each do |c|
            [c[:file], c[:heading], c[:excerpt]].compact.each do |v|
              unless secrets_ok?(v.to_s)
                errors << "citation contains secrets pattern"
                break
              end
            end
          end
          if result.data.is_a?(Hash)
            unless secrets_ok?(result.data.to_json)
              errors << "result.data contains secrets pattern"
            end
          end

          errors
        end

        def secrets_ok?(text)
          return true if text.blank?

          sanitized = ::Ai::MessageSanitizer.sanitize(text)
          !sanitized.include?(::Ai::MessageSanitizer::REDACT_PLACEHOLDER)
        end
      end
    end
  end
end
