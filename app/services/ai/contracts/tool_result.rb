# frozen_string_literal: true

module Ai
  module Contracts
    # Contract for deterministic tool execution result (Executor output).
    # Stable keys: success, tool_name, data, error, error_code, metadata, authorization_denied, latency_ms.
    class ToolResult
      attr_reader :success, :tool_name, :data, :error, :error_code, :metadata,
                  :authorization_denied, :latency_ms, :contract_version

      def initialize(
        success: false,
        tool_name: '',
        data: nil,
        error: nil,
        error_code: nil,
        metadata: {},
        authorization_denied: false,
        latency_ms: nil,
        contract_version: nil
      )
        @success = !!success
        @tool_name = tool_name.to_s.strip.presence || ''
        @data = data
        @error = error.to_s.strip.presence
        @error_code = error_code.to_s.strip.presence
        @metadata = metadata.is_a?(Hash) ? metadata : {}
        @authorization_denied = !!authorization_denied
        @latency_ms = latency_ms.is_a?(Integer) ? latency_ms : nil
        @contract_version = contract_version || Contracts::TOOL_RESULT_VERSION
      end

      def self.from_h(h)
        return nil if h.blank? || !h.is_a?(Hash)

        sym = h.with_indifferent_access
        new(
          success: !!sym[:success],
          tool_name: sym[:tool_name].to_s,
          data: sym[:data],
          error: sym[:error],
          error_code: sym[:error_code],
          metadata: sym[:metadata].to_h,
          authorization_denied: !!sym[:authorization_denied],
          latency_ms: sym[:latency_ms],
          contract_version: sym[:contract_version].presence
        )
      end

      def success?
        @success
      end

      def authorization_denied?
        @authorization_denied
      end

      def to_h
        out = {
          success: @success,
          tool_name: @tool_name,
          data: @data,
          error: @error,
          error_code: @error_code,
          metadata: @metadata.merge(contract_version: @contract_version),
          contract_version: @contract_version
        }
        out[:authorization_denied] = true if @authorization_denied
        out[:latency_ms] = @latency_ms if @latency_ms.present?
        out
      end

      def validate!
        return true unless Rails.env.development? || Rails.env.test?
        raise ArgumentError, 'ToolResult: tool_name required' if @tool_name.blank?
        true
      end
    end
  end
end
