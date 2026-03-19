# frozen_string_literal: true

# Webhook configuration
# Set WEBHOOK_SECRET environment variable or configure in credentials
# For development, a default secret is used if not set

DEFAULT_DEV_SECRET = 'default_webhook_secret_for_development_only'

Rails.application.config.webhook_secret = ENV['WEBHOOK_SECRET'].presence ||
                                          Rails.application.credentials[:webhook_secret] ||
                                          DEFAULT_DEV_SECRET

# Security: in production, warn or fail if using default dev secret (see docs/SECURITY_REVIEW.md)
if Rails.env.production? && Rails.application.config.webhook_secret == DEFAULT_DEV_SECRET
  Rails.logger.error('[WebhookConfig] WEBHOOK_SECRET is not set in production; using default. Forged webhooks will be accepted. Set WEBHOOK_SECRET.')
  if ENV['WEBHOOK_SECRET_STRICT'].to_s.strip.downcase.in?(%w[true 1])
    raise 'WEBHOOK_SECRET must be set in production. Set WEBHOOK_SECRET or disable WEBHOOK_SECRET_STRICT.'
  end
end
