# frozen_string_literal: true

module Ai
  module Agents
    class SupportFaqAgent < BaseAgent
      def system_instructions
        super + "\nYou are the support/FAQ agent. Answer questions about refunds, payment statuses, API usage, and general how-to using the provided docs. Be concise."
      end
    end
  end
end
