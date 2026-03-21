# frozen_string_literal: true

# Fail-fast validation of AI agent and tool registries in development/test.
# Ensures registered classes exist, metadata is present, and capability rules hold.
Rails.application.config.after_initialize do
  next unless Rails.env.development? || Rails.env.test?

  begin
    Ai::Skills::Registry.validate!
    Ai::AgentRegistry.validate!
    Ai::Tools::Registry.validate!
  rescue ArgumentError => e
    Rails.logger.error("[AI registries] #{e.message}")
    raise
  end
end
