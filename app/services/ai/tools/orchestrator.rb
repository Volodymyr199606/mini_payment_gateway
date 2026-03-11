# frozen_string_literal: true

module Ai
  module Tools
    # Invokes at most one tool when message matches a clear intent.
    # Returns { invoked: true, result:, reply_text: } or { invoked: false }.
    class Orchestrator
      MAX_TOOL_CALLS_PER_REQUEST = 1

      def self.invoke_if_applicable(message:, merchant_id: nil, request_id: nil)
        new(message: message, merchant_id: merchant_id, request_id: request_id).call
      end

      def initialize(message:, merchant_id: nil, request_id: nil)
        @message = message
        @merchant_id = merchant_id
        @request_id = request_id
      end

      def call
        intent = IntentDetector.detect(@message)
        return { invoked: false } unless intent
        return { invoked: false } unless @merchant_id.present?

        context = { merchant_id: @merchant_id, request_id: @request_id }
        result = Executor.call(
          tool_name: intent[:tool_name],
          args: intent[:args],
          context: context
        )

        reply_text = format_reply(result)
        {
          invoked: true,
          result: result,
          reply_text: reply_text,
          tool_name: intent[:tool_name]
        }
      end

      private

      def format_reply(executor_result)
        return 'Could not fetch data.' unless executor_result[:success]
        return 'No data.' if executor_result[:data].blank?

        Formatter.format(executor_result[:tool_name], executor_result[:data])
      end
    end
  end
end
