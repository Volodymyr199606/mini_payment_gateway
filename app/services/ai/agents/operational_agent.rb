# frozen_string_literal: true

module Ai
  module Agents
    class OperationalAgent < BaseAgent
      def system_instructions
        super + "\nYou are the operational agent. Explain payment lifecycle (authorize, capture, void, refund), statuses, and chargebacks/disputes based on the provided docs only."
      end
    end
  end
end
