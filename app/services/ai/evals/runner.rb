# frozen_string_literal: true

module Ai
  module Evals
    # Eval harness: load golden questions YAML, run router -> retrieval -> agent per case,
    # collect structured results (agent match, must_include, must_not_include, citations).
    # Test-friendly: caller stubs GroqClient and Reporting::LedgerSummary; optional dependency injection.
    class Runner
      DEFAULT_FIXTURE_PATH = Rails.root.join('spec/fixtures/ai/golden_questions.yml')
      LEGACY_FIXTURE_PATH = Rails.root.join('spec/ai/golden_questions.yml')
      RESPONSE_EXCERPT_LENGTH = 200

      class << self
        # Load and flatten golden questions. Returns array of hashes with symbol keys.
        # Each entry: id:, question:, expected_agent:, must_include:, must_not_include:, require_citations:, deterministic:
        def load_questions(path = nil)
          path = path || (DEFAULT_FIXTURE_PATH.exist? ? DEFAULT_FIXTURE_PATH : LEGACY_FIXTURE_PATH)
          return [] unless path.exist?

          raw = YAML.load_file(path)
          flatten_cases(raw)
        end

        # Run all cases. Returns array of result hashes.
        # Options: merchant_id (required for reporting), router:, retrieval: (callables for DI).
        def run_all(merchant_id:, path: nil, router: nil, retrieval: nil)
          cases = load_questions(path)
          cases.map { |c| run_one(c, merchant_id: merchant_id, router: router, retrieval: retrieval) }
        end

        # Run a single case. Returns result hash with passed_* and metadata.
        def run_one(case_hash, merchant_id:, router: nil, retrieval: nil)
          id = case_hash[:id] || case_hash['id']
          question = (case_hash[:question] || case_hash['question']).to_s.strip
          expected_agent = (case_hash[:expected_agent] || case_hash['expected_agent']).to_sym
          must_include = Array(case_hash[:must_include] || case_hash['must_include'])
          must_not_include = Array(case_hash[:must_not_include] || case_hash['must_not_include'])
          require_citations = case_hash[:require_citations] || case_hash['require_citations']
          require_citations = false if require_citations.nil?

          # Resolve router and retrieval
          agent_key = if router.respond_to?(:call)
            router.call(question)
          else
            ::Ai::Router.new(question).call
          end

          retriever_result = if retrieval.respond_to?(:call)
            retrieval.call(question, agent_key)
          else
            ::Ai::Rag::RetrievalService.call(question, agent_key: agent_key)
          end

          context_text = retriever_result[:context_text]
          citations = retriever_result[:citations] || []
          citations_count = citations.size

          agent_class = ::Ai::AgentRegistry.fetch(agent_key)
          agent = build_agent(agent_class, agent_key, question, context_text, citations, merchant_id: merchant_id)
          result = agent.call

          reply_text = result.respond_to?(:reply_text) ? result.reply_text.to_s : ''
          result_citations = result.respond_to?(:citations) ? result.citations.to_a : []

          passed_agent_match = (expected_agent.to_sym == agent_key.to_sym)
          passed_required_content = check_must_include(reply_text, must_include)
          passed_forbidden_content = check_must_not_include(reply_text, must_not_include)
          passed_citations = require_citations ? result_citations.size >= 1 : true
          passed_overall = passed_agent_match && passed_required_content && passed_forbidden_content && passed_citations

          failure_reasons = []
          failure_reasons << 'agent_mismatch' unless passed_agent_match
          failure_reasons << 'missing_required_content' unless passed_required_content
          failure_reasons << 'forbidden_content' unless passed_forbidden_content
          failure_reasons << 'citations_required' unless passed_citations

          {
            id: id.to_s,
            question: question,
            expected_agent: expected_agent,
            actual_agent: agent_key,
            passed_agent_match: passed_agent_match,
            passed_required_content: passed_required_content,
            passed_forbidden_content: passed_forbidden_content,
            passed_citations: passed_citations,
            passed_overall: passed_overall,
            response_excerpt: reply_text.to_s[0, RESPONSE_EXCERPT_LENGTH],
            citations_count: result_citations.size,
            metadata: {
              failure_reasons: failure_reasons,
              deterministic: case_hash[:deterministic] || case_hash['deterministic']
            }
          }
        rescue StandardError => e
          {
            id: (case_hash[:id] || case_hash['id']).to_s,
            question: (case_hash[:question] || case_hash['question']).to_s.strip,
            expected_agent: (case_hash[:expected_agent] || case_hash['expected_agent']).to_sym,
            actual_agent: nil,
            passed_agent_match: false,
            passed_required_content: false,
            passed_forbidden_content: false,
            passed_citations: false,
            passed_overall: false,
            response_excerpt: '',
            citations_count: 0,
            metadata: { error: e.message, backtrace: e.backtrace&.first(3) }
          }
        end

        # Human-readable summary. Prints to stdout; returns summary hash.
        def print_summary(results)
          total = results.size
          passed = results.count { |r| r[:passed_overall] }
          failed = total - passed
          by_agent = results.group_by { |r| (r[:expected_agent] || r[:actual_agent]).to_s }
          failed_by_category = by_agent.transform_values { |v| v.count { |x| !x[:passed_overall] } }.select { |_, c| c > 0 }

          puts "Eval summary: #{passed}/#{total} passed, #{failed} failed"
          if failed_by_category.any?
            category_str = failed_by_category.map { |k, v| "#{k}=#{v}" }.join(', ')
            puts "Failures by category: #{category_str}"
            results.select { |r| !r[:passed_overall] }.each do |r|
              reasons = r.dig(:metadata, :failure_reasons) || r.dig(:metadata, :error) || ['unknown']
              puts "  [#{r[:id]}] #{reasons.is_a?(Array) ? reasons.join(', ') : reasons}: #{r[:question].to_s[0, 60]}..."
            end
          end
          {
            total: total,
            passed: passed,
            failed: failed,
            failed_by_category: failed_by_category,
            results: results
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

        private

        def flatten_cases(raw)
          return [] if raw.blank?

          list = []
          raw = raw.to_h
          raw.each do |group_key, items|
            group_agent = group_key.to_sym
            Array(items).each do |item|
              entry = item.is_a?(Hash) ? item.deep_symbolize_keys : { question: item.to_s.strip, expected_agent: group_agent }
              entry[:expected_agent] = group_agent if entry[:expected_agent].blank?
              entry[:must_include] ||= []
              entry[:must_not_include] ||= []
              entry[:require_citations] = false if entry[:require_citations].nil?
              entry[:deterministic] = false if entry[:deterministic].nil?
              entry[:id] ||= "#{group_key}-#{list.size}"
              list << entry
            end
          end
          list
        end

        def check_must_include(reply, phrases)
          return true if phrases.blank?

          normalized = reply.to_s.downcase
          phrases.all? { |p| normalized.include?(p.to_s.downcase) }
        end

        def check_must_not_include(reply, phrases)
          return true if phrases.blank?

          normalized = reply.to_s.downcase
          phrases.none? { |p| normalized.include?(p.to_s.downcase) }
        end
      end
    end
  end
end
