# frozen_string_literal: true

# AI configuration and startup validation.
# - FeatureFlags and RuntimeConfig are loaded on first use.
# - StartupValidator runs after initialize; in dev/test it raises on invalid config.
Rails.application.config.after_initialize do
  begin
    Ai::Config::StartupValidator.call
  rescue Ai::Config::StartupValidator::ValidationError => e
    Rails.logger.error("[Ai::Config] #{e.message}")
    raise
  end
end
