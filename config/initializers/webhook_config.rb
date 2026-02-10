# frozen_string_literal: true

# Webhook configuration
# Set WEBHOOK_SECRET environment variable or configure in credentials
# For development, a default secret is used if not set

Rails.application.config.webhook_secret = ENV['WEBHOOK_SECRET'] ||
                                          Rails.application.credentials[:webhook_secret] ||
                                          'default_webhook_secret_for_development_only'
