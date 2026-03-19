# frozen_string_literal: true

Rails.application.config.after_initialize do
  begin
    Payments::Config.validate!
  rescue Payments::ProviderConfigurationError => e
    Rails.logger.error(e.message)
    raise
  end
end

Rails.application.config.to_prepare do
  Payments::ProviderRegistry.reset!
end
