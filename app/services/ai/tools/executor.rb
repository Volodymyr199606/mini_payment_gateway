# frozen_string_literal: true

module Ai
  module Tools
    # Executes a deterministic tool: resolve, validate, run, return structured result.
    # Max 1 tool call per request (caller enforces).
    class Executor
      def self.call(tool_name:, args: {}, context: {})
        new(tool_name: tool_name, args: args, context: context).call
      end

      def initialize(tool_name:, args: {}, context: {})
        @tool_name = tool_name.to_s.strip
        @args = args.to_h
        @context = context.to_h.stringify_keys
      end

      def call
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        unless Registry.known?(@tool_name)
          return log_and_return(failure(error: 'Unknown tool', error_code: 'unknown_tool'), started_at)
        end

        tool_class = Registry.resolve(@tool_name)
        tool = tool_class.new(args: @args, context: @context)
        result = tool.call

        log_and_return(build_result(result, tool_class), started_at)
      rescue StandardError => e
        log_and_return(
          failure(error: e.message, error_code: 'execution_error'),
          started_at
        )
      end

      private

      def build_result(tool_output, _tool_class)
        if tool_output[:success]
          {
            success: true,
            tool_name: @tool_name,
            data: tool_output[:data],
            error: nil,
            metadata: { source: 'tool' }
          }
        else
          {
            success: false,
            tool_name: @tool_name,
            data: nil,
            error: tool_output[:error],
            error_code: tool_output[:error_code],
            metadata: {}
          }
        end
      end

      def failure(error:, error_code:)
        {
          success: false,
          tool_name: @tool_name,
          data: nil,
          error: error,
          error_code: error_code,
          metadata: {}
        }
      end

      def log_and_return(result, started_at)
        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        Ai::Observability::EventLogger.log_tool_call(
          request_id: @context['request_id'],
          merchant_id: @context['merchant_id'],
          tool_name: @tool_name,
          args: sanitize_args(@args),
          success: result[:success],
          latency_ms: latency_ms
        )
        result.merge(metadata: (result[:metadata] || {}).merge(latency_ms: latency_ms))
      end

      def sanitize_args(args)
        return {} if args.blank?

        args.to_h.stringify_keys.except('api_key', 'token', 'secret', 'password')
      end
    end
  end
end
