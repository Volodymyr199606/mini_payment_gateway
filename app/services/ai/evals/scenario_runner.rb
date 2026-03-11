# frozen_string_literal: true

module Ai
  module Evals
    # End-to-end scenario runner: orchestrates full AI flow (orchestration or agent path),
    # stubs external LLM, collects structured results for assertion.
    # Use with spec/fixtures/ai/scenarios.yml.
    class ScenarioRunner
      DEFAULT_FIXTURE_PATH = Rails.root.join('spec/fixtures/ai/scenarios.yml')
      STUB_REPLY = 'Stub reply for scenario eval. No external API.'
      REQUEST_ID_PREFIX = 'scenario-eval'

      class << self
        # Load scenarios from YAML. Returns array of hashes with symbol keys.
        def load_scenarios(path = nil)
          path = path || DEFAULT_FIXTURE_PATH
          return [] unless path.to_s.present? && File.exist?(path.to_s)

          raw = YAML.load_file(path.to_s)
          list = raw.is_a?(Hash) ? (raw['scenarios'] || raw[:scenarios] || []) : Array(raw)
          list.map { |s| normalize_scenario(s) }
        end

        # Run a single scenario. Returns result hash with passed_* and metadata.
        # Caller must stub Ai::GroqClient, Ai::Generation::StreamingClient, Reporting::LedgerSummary before calling.
        # Options: merchant_id (required), entity_ids (hash of created entity id mappings for substitution).
        def run_one(scenario, merchant_id:, entity_ids: {})
          msg = resolve_message(scenario, entity_ids)
          request_id = "#{REQUEST_ID_PREFIX}-#{scenario[:id]}"
          Thread.current[:ai_request_id] = request_id

          result = execute_flow(msg, merchant_id: merchant_id, request_id: request_id)
          result[:scenario_id] = scenario[:id]
          result[:user_message] = msg
          result[:expected] = scenario
          result[:passed_overall] = compute_passed_overall(result, scenario)
          result[:failure_summary] = build_failure_summary(result, scenario) unless result[:passed_overall]
          result
        rescue StandardError => e
          {
            scenario_id: scenario[:id],
            user_message: msg,
            expected: scenario,
            passed_overall: false,
            error: e.message,
            backtrace: e.backtrace&.first(5),
            failure_summary: "Error: #{e.message}"
          }
        end

        # Run all scenarios. Returns array of result hashes.
        def run_all(merchant_id:, path: nil, entity_factory: nil)
          scenarios = load_scenarios(path)
          scenarios.map do |s|
            ids = entity_factory.respond_to?(:call) ? entity_factory.call(s, merchant_id) : {}
            run_one(s, merchant_id: merchant_id, entity_ids: ids)
          end
        end

        # Human-readable failure summary. Call with failed result.
        def failure_summary(result)
          result[:failure_summary] || build_failure_summary(result, result[:expected] || {})
        end

        # Print summary to stdout. Returns summary hash.
        def print_summary(results)
          total = results.size
          passed = results.count { |r| r[:passed_overall] }
          failed = total - passed
          puts "Scenario eval: #{passed}/#{total} passed, #{failed} failed"
          results.reject { |r| r[:passed_overall] }.each do |r|
            puts "  [#{r[:scenario_id]}] #{r[:failure_summary] || r[:error]}"
          end
          { total: total, passed: passed, failed: failed, results: results }
        end

        private

        def normalize_scenario(raw)
          h = raw.is_a?(Hash) ? raw.deep_symbolize_keys : {}
          {
            id: h[:id].to_s,
            description: h[:description].to_s,
            user_message: (h[:user_message] || h[:question]).to_s,
            entity_refs: Array(h[:entity_refs]).map(&:to_s),
            expected_path: (h[:expected_path] || 'docs_only').to_s,
            expected_agent: (h[:expected_agent] || '').to_s,
            expected_tool_names: Array(h[:expected_tool_names]).map(&:to_s),
            require_citations: h.fetch(:require_citations, false),
            expected_response_must_include: Array(h[:expected_response_must_include]),
            expected_response_must_not_include: Array(h[:expected_response_must_not_include]),
            expected_audit_fields: Array(h[:expected_audit_fields]),
            expected_debug_fields: Array(h[:expected_debug_fields])
          }
        end

        def resolve_message(scenario, entity_ids)
          msg = scenario[:user_message].to_s
          entity_ids.each do |key, val|
            placeholder = "{{#{key}}}"
            msg = msg.gsub(placeholder, val.to_s) if val.present?
          end
          msg
        end

        def execute_flow(msg, merchant_id:, request_id:)
          # 1. Orchestration (ConstrainedRunner) - matches dashboard flow
          run_result = Ai::Orchestration::ConstrainedRunner.call(
            message: msg,
            merchant_id: merchant_id,
            request_id: request_id
          )

          if run_result.orchestration_used?
            return collect_orchestration_result(run_result, request_id, merchant_id)
          end

          # 2. Agent path: Router -> Retrieval -> Agent
          collect_agent_path_result(msg, merchant_id: merchant_id, request_id: request_id)
        end

        def collect_orchestration_result(run_result, request_id, merchant_id)
          agent_key = run_result.step_count > 1 ? 'orchestration' : "tool:#{run_result.tool_names.first}"
          composed = Ai::ResponseComposer.call(
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
          audit_record = write_and_capture_audit(
            request_id: request_id,
            endpoint: 'scenario',
            merchant_id: merchant_id,
            agent_key: composed[:agent_key],
            composition: composed[:composition],
            tool_used: true,
            tool_names: run_result.tool_names.to_a,
            citations_count: 0,
            latency_ms: run_result.metadata[:latency_ms],
            success: run_result.success?,
            orchestration_used: true,
            orchestration_step_count: run_result.step_count,
            orchestration_halted_reason: run_result.halted_reason
          )
          {
            path: run_result.step_count > 1 ? 'orchestration' : 'tool_only',
            agent_key: composed[:agent_key],
            tool_names: run_result.tool_names.to_a,
            composition_mode: composed.dig(:composition, :composition_mode),
            reply_text: composed[:reply],
            citations: composed[:citations],
            citations_count: 0,
            audit: audit_record,
            debug: {
              tool_used: run_result.tool_names.first,
              orchestration_used: true,
              orchestration_step_count: run_result.step_count
            }
          }
        end

        def collect_agent_path_result(msg, merchant_id:, request_id:)
          agent_key = Ai::Router.new(msg).call
          agent_key = Ai::AgentRegistry.default_key unless Ai::AgentRegistry.all_keys.include?(agent_key)
          retriever_result = Ai::Rag::RetrievalService.call(msg, agent_key: agent_key)
          context_text = retriever_result[:context_text]
          citations = retriever_result[:citations] || []
          agent_class = Ai::AgentRegistry.fetch(agent_key)
          agent = build_agent(agent_class, agent_key, msg, context_text, citations, merchant_id: merchant_id)
          result = agent.call
          reply_text = result.respond_to?(:reply_text) ? result.reply_text.to_s : ''
          result_citations = result.respond_to?(:citations) ? result.citations.to_a : []
          composed = Ai::ResponseComposer.call(
            reply_text: reply_text,
            citations: result_citations,
            agent_key: result.agent_key,
            model_used: result.model_used,
            fallback_used: result.fallback_used,
            data: result.data,
            memory_used: false
          )
          audit_record = write_and_capture_audit(
            request_id: request_id,
            endpoint: 'scenario',
            merchant_id: merchant_id,
            agent_key: composed[:agent_key],
            composition: composed[:composition],
            tool_used: composed.dig(:composition, :used_tool_data),
            tool_names: [],
            citations_count: result_citations.size,
            latency_ms: 0,
            success: true,
            retriever_key: retriever_result.dig(:debug, :retriever)
          )
          {
            path: composed.dig(:composition, :composition_mode) || 'docs_only',
            agent_key: composed[:agent_key],
            tool_names: [],
            composition_mode: composed.dig(:composition, :composition_mode),
            reply_text: composed[:reply],
            citations: result_citations,
            citations_count: result_citations.size,
            audit: audit_record,
            debug: { selected_agent: composed[:agent_key], citations_count: result_citations.size }
          }
        end

        def write_and_capture_audit(**attrs)
          record = Ai::AuditTrail::RecordBuilder.call(**attrs)
          Ai::AuditTrail::Writer.write(record)
          AiRequestAudit.where(request_id: attrs[:request_id]).last
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

        def compute_passed_overall(result, scenario)
          return false if result[:error]

          passed_path = path_matches?(result[:path], scenario[:expected_path])
          passed_agent = agent_matches?(result[:agent_key], scenario[:expected_agent])
          passed_tools = tools_match?(result[:tool_names], scenario[:expected_tool_names])
          passed_include = check_must_include(result[:reply_text], scenario[:expected_response_must_include])
          passed_not_include = check_must_not_include(result[:reply_text], scenario[:expected_response_must_not_include])
          passed_citations = scenario[:require_citations] ? (result[:citations_count].to_i >= 1) : true
          passed_audit = audit_fields_present?(result[:audit], scenario[:expected_audit_fields])

          result[:passed_path] = passed_path
          result[:passed_agent] = passed_agent
          result[:passed_tools] = passed_tools
          result[:passed_include] = passed_include
          result[:passed_not_include] = passed_not_include
          result[:passed_citations] = passed_citations
          result[:passed_audit] = passed_audit

          passed_path && passed_agent && passed_tools && passed_include && passed_not_include && passed_citations && passed_audit
        end

        def path_matches?(actual, expected)
          return true if expected.blank?

          actual_path = (actual || '').to_s
          exp_path = expected.to_s
          return true if actual_path == exp_path
          return true if exp_path == 'tool_only' && actual_path == 'tool_only'
          return true if exp_path == 'orchestration' && actual_path == 'orchestration'
          return true if exp_path == 'docs_only' && %w[docs_only memory_docs].include?(actual_path)

          false
        end

        def agent_matches?(actual, expected)
          return true if expected.blank?

          (actual || '').to_s == expected.to_s
        end

        def tools_match?(actual, expected)
          return true if expected.blank?

          Array(actual).map(&:to_s).sort == Array(expected).map(&:to_s).sort
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

        def audit_fields_present?(audit, fields)
          return true if fields.blank?

          return false unless audit.present?

          fields.all? do |f|
            key = f.to_s.underscore
            next false unless audit.respond_to?(key)

            val = audit.send(key)
            val.is_a?(FalseClass) ? true : val.present?
          end
        rescue StandardError
          false
        end

        def build_failure_summary(result, scenario)
          parts = []
          parts << "path: expected #{scenario[:expected_path]}, got #{result[:path]}" unless result[:passed_path]
          parts << "agent: expected #{scenario[:expected_agent]}, got #{result[:agent_key]}" unless result[:passed_agent]
          parts << "tools: expected #{scenario[:expected_tool_names]}, got #{result[:tool_names]}" unless result[:passed_tools]
          parts << 'missing required content' unless result[:passed_include]
          parts << 'contains forbidden content' unless result[:passed_not_include]
          parts << 'citations required' unless result[:passed_citations]
          parts << 'audit fields missing' unless result[:passed_audit]
          parts.join('; ')
        end
      end
    end
  end
end
