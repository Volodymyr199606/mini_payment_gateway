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

        engine = ::Ai::Policy::Engine.call(context: @context, parsed_request: { args: @args })
        tool_decision = engine.allow_tool?(tool_name: @tool_name, parsed_request: { args: @args })
        if tool_decision.denied?
          return log_and_return(
            failure(error: ::Ai::Policy::Engine.denied_message, error_code: 'access_denied', authorization_denied: true),
            started_at
          )
        end

        # Cache lookup for safe read-only tools
        cached = fetch_cached_result(started_at)
        return cached if cached

        tool_class = Registry.resolve(@tool_name)
        tool = tool_class.new(args: @args, context: @context)
        tool_output = tool.call
        built = build_result(tool_output, tool_class)
        write_cached_result(built, started_at) if built[:success]
        log_and_return(built, started_at)
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

      def failure(error:, error_code:, authorization_denied: false)
        out = {
          success: false,
          tool_name: @tool_name,
          data: nil,
          error: error,
          error_code: error_code,
          metadata: {}
        }
        out[:authorization_denied] = true if authorization_denied
        out
      end

      def log_and_return(result, started_at)
        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        auth_denied = result[:authorization_denied] || result[:error_code] == 'access_denied'
        Ai::Observability::EventLogger.log_tool_call(
          request_id: @context['request_id'],
          merchant_id: @context['merchant_id'],
          tool_name: @tool_name,
          args: sanitize_args(@args),
          success: result[:success],
          latency_ms: latency_ms,
          authorization_denied: auth_denied,
          tool_blocked_by_policy: auth_denied
        )
        merged = result.merge(metadata: (result[:metadata] || {}).merge(latency_ms: latency_ms))
        merged[:authorization_denied] = true if auth_denied
        merged
      end

      def sanitize_args(args)
        return {} if args.blank?

        args.to_h.stringify_keys.except('api_key', 'token', 'secret', 'password')
      end

      def fetch_cached_result(started_at)
        return nil unless ::Ai::Performance::CachePolicy.cacheable_tool?(@tool_name)
        return nil if ::Ai::Performance::CachePolicy.bypass?

        merchant_id = @context['merchant_id']&.to_i
        return nil unless merchant_id.present?

        key = ::Ai::Performance::CacheKeys.tool(merchant_id: merchant_id, tool_name: @tool_name, args: @args)
        category = ::Ai::Performance::CachePolicy.tool_category(@tool_name)
        raw = Rails.cache.read(key)
        return nil unless raw.is_a?(Hash) && raw['success'] == true

        result = raw.stringify_keys.transform_keys(&:to_sym)
        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        result = result.merge(metadata: (result[:metadata] || {}).merge(latency_ms: latency_ms))
        ::Ai::Observability::EventLogger.log_cache(
          cache_category: category,
          cache_key_fingerprint: ::Ai::Performance::CacheKeys.fingerprint(key),
          cache_outcome: 'hit',
          cache_ttl: ::Ai::Performance::CachePolicy.ttl_for(category)
        )
        log_and_return(result, started_at)
      rescue StandardError
        nil
      end

      def write_cached_result(result, started_at)
        return unless result[:success] && result[:data].present?
        return unless ::Ai::Performance::CachePolicy.cacheable_tool?(@tool_name)
        return if ::Ai::Performance::CachePolicy.bypass?

        merchant_id = @context['merchant_id']&.to_i
        return unless merchant_id.present?

        key = ::Ai::Performance::CacheKeys.tool(merchant_id: merchant_id, tool_name: @tool_name, args: @args)
        category = ::Ai::Performance::CachePolicy.tool_category(@tool_name)
        storeable = result.merge(metadata: (result[:metadata] || {}).except(:latency_ms))
        Rails.cache.write(key, storeable.stringify_keys, expires_in: ::Ai::Performance::CachePolicy.ttl_for(category))
      rescue StandardError
        nil
      end
    end
  end
end
