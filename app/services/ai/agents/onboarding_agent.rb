# frozen_string_literal: true

module Ai
  module Agents
    class OnboardingAgent < BaseAgent
      def system_instructions
        super + "\nYou are the developer onboarding agent. Help with integration: endpoints, idempotency keys, webhooks, API keys, and example requests. Point to specific docs and headings."
      end
    end
  end
end
