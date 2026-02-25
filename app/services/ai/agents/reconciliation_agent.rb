# frozen_string_literal: true

module Ai
  module Agents
    class ReconciliationAgent < BaseAgent
      def system_instructions
        super + "\nYou are the reconciliation analyst agent. Provide design guidance only. You MUST clearly state that reconciliation is NOT implemented yet in this gateway. Explain what reconciliation would involve (matching internal ledger to processor/bank settlement) and suggest what docs or features could be added later."
      end
    end
  end
end
