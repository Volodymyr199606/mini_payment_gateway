# frozen_string_literal: true

module Ai
  module Agents
    class SecurityAgent < BaseAgent
      def system_instructions
        super + "\nYou are the security/compliance agent. Answer about PCI, PAN, tokenization, logging, and webhook signatures. Emphasize: never store raw card numbers; use tokens only."
      end
    end
  end
end
