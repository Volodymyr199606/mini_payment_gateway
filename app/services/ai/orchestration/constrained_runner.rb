# frozen_string_literal: true

module Ai
  module Orchestration
    # Constrained multi-step tool orchestration. Max 2 steps, no recursion, no loops.
    # Only runs when intent is clear; only allows explicit follow-up chains (e.g. transaction -> payment intent).
    # Deterministic tools only; tool outputs remain source of truth.
    class ConstrainedRunner
      MAX_STEPS = 2

      # Allowed follow-up: after get_transaction, we may call get_payment_intent if result has payment_intent_id.
      FOLLOW_UP_RULES = {
        'get_transaction' => { next_tool: 'get_payment_intent', arg_from: 'payment_intent_id' }
      }.freeze

      def self.call(message:, merchant_id: nil, request_id: nil, resolved_intent: nil)
        new(message: message, merchant_id: merchant_id, request_id: request_id, resolved_intent: resolved_intent).call
      end

      def initialize(message:, merchant_id: nil, request_id: nil, resolved_intent: nil)
        @message = message.to_s.strip
        @merchant_id = merchant_id
        @request_id = request_id.to_s.strip.presence
        @resolved_intent = resolved_intent
      end

      def call
        return RunResult.no_orchestration if @message.blank?
        return RunResult.no_orchestration unless @merchant_id.present?

        intent = @resolved_intent || ::Ai::Tools::IntentDetector.detect(@message)
        return RunResult.no_orchestration unless intent

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        context = { merchant_id: @merchant_id, request_id: @request_id }
        steps = []
        tool_names = []
        deterministic_data = nil
        reply_parts = []
        halted_reason = nil

        # Step 1
        step1_result = ::Ai::Tools::Executor.call(
          tool_name: intent[:tool_name],
          args: intent[:args],
          context: context
        )
        step1_record = build_step_record(intent[:tool_name], intent[:args], step1_result)
        steps << step1_record
        tool_names << intent[:tool_name]

        if step1_result[:success] && step1_result[:data].present?
          reply_parts << ::Ai::Tools::Formatter.format(intent[:tool_name], step1_result[:data])
        else
          reply_parts << format_step_failure(intent[:tool_name], step1_result)
        end

        # Step 2 only when allowed by rules and step 1 succeeded with linkable data
        rule = FOLLOW_UP_RULES[intent[:tool_name].to_s]
        if steps.size < MAX_STEPS && rule && step1_result[:success] && step1_result[:data].is_a?(Hash)
          data = step1_result[:data]
          next_arg_value = data[rule[:arg_from]] || data[rule[:arg_from].to_s] || data[rule[:arg_from].to_sym]
          if next_arg_value.present?
            step2_args = { rule[:arg_from] => next_arg_value }
            step2_result = ::Ai::Tools::Executor.call(
              tool_name: rule[:next_tool],
              args: step2_args,
              context: context
            )
            step2_record = build_step_record(rule[:next_tool], step2_args, step2_result)
            steps << step2_record
            tool_names << rule[:next_tool]

            if step2_result[:success] && step2_result[:data].present?
              reply_parts << ::Ai::Tools::Formatter.format(rule[:next_tool], step2_result[:data])
              deterministic_data = build_merged_data(intent[:tool_name], step1_result[:data], rule[:next_tool], step2_result[:data])
            else
              reply_parts << format_step_failure(rule[:next_tool], step2_result)
              deterministic_data = { intent[:tool_name].sub(/\Aget_/, '') => step1_result[:data] }
            end
          else
            halted_reason = 'no_follow_up_id'
            deterministic_data = step1_result[:data]
          end
        else
          halted_reason = 'single_step' if steps.size == 1 && rule.nil?
          halted_reason = 'follow_up_not_allowed' if steps.size == 1 && rule && !step1_result[:success]
          deterministic_data = step1_result[:data] if step1_result[:success]
        end

        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        success = steps.any? { |s| s[:success] }
        reply_text = reply_parts.join("\n\n")

        log_orchestration_run(
          step_count: steps.size,
          tool_names: tool_names,
          success: success,
          halted_reason: halted_reason,
          latency_ms: latency_ms
        )

        RunResult.new(
          orchestration_used: true,
          step_count: steps.size,
          steps: steps,
          tool_names: tool_names,
          success: success,
          halted_reason: halted_reason,
          deterministic_data: deterministic_data,
          metadata: { latency_ms: latency_ms },
          reply_text: reply_text
        )
      end

      private

      def build_step_record(tool_name, args, executor_result)
        {
          tool_name: tool_name,
          validated_args: sanitize_args(args),
          success: executor_result[:success],
          result_summary: result_summary_safe(executor_result),
          latency_ms: executor_result.dig(:metadata, :latency_ms)
        }.compact
      end

      def sanitize_args(args)
        return {} if args.blank?

        args.to_h.stringify_keys.except('api_key', 'token', 'secret', 'password')
      end

      def result_summary_safe(executor_result)
        return 'failure' unless executor_result[:success]
        return 'empty' if executor_result[:data].blank?

        'found'
      end

      def format_step_failure(tool_name, executor_result)
        return 'Could not fetch data.' if executor_result[:error].present?

        "Could not fetch #{tool_name.sub(/\Aget_/, '').tr('_', ' ')}."
      end

      def build_merged_data(first_tool, first_data, second_tool, second_data)
        key1 = first_tool.to_s.sub(/\Aget_/, '').to_sym
        key2 = second_tool.to_s.sub(/\Aget_/, '').to_sym
        { key1 => first_data, key2 => second_data }
      end

      def log_orchestration_run(step_count:, tool_names:, success:, halted_reason:, latency_ms:)
        ::Ai::Observability::EventLogger.log_orchestration_run(
          request_id: @request_id,
          merchant_id: @merchant_id,
          step_count: step_count,
          tool_names: tool_names,
          success: success,
          halted_reason: halted_reason,
          latency_ms: latency_ms
        )
      end
    end
  end
end
