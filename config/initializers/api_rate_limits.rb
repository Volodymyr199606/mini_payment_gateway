# frozen_string_literal: true

# Central configuration for API v1 rate limits (per category, per window).
# Override via ENV for production tuning without code changes.
module ApiRateLimits
  WINDOW_SECONDS = ENV.fetch('API_RATE_LIMIT_WINDOW_SECONDS', '60').to_i.clamp(1, 3600)

  # All limits are "max requests per WINDOW_SECONDS" unless noted.
  CATEGORIES = {
    'payment_mutation' => {
      limit: ENV.fetch('API_RATE_LIMIT_PAYMENT_MUTATION', '120').to_i.clamp(1, 1_000_000),
      window_seconds: WINDOW_SECONDS
    },
    'read' => {
      limit: ENV.fetch('API_RATE_LIMIT_READ', '600').to_i.clamp(1, 1_000_000),
      window_seconds: WINDOW_SECONDS
    },
    'resource_write' => {
      limit: ENV.fetch('API_RATE_LIMIT_RESOURCE_WRITE', '180').to_i.clamp(1, 1_000_000),
      window_seconds: WINDOW_SECONDS
    },
    'auth_account' => {
      limit: ENV.fetch('API_RATE_LIMIT_AUTH_ACCOUNT', '120').to_i.clamp(1, 1_000_000),
      window_seconds: WINDOW_SECONDS
    },
    'ai' => {
      limit: ENV.fetch('API_RATE_LIMIT_AI', '20').to_i.clamp(1, 1_000_000),
      window_seconds: ENV.fetch('API_RATE_LIMIT_AI_WINDOW_SECONDS', '60').to_i.clamp(1, 3600)
    },
    'webhook_ingress' => {
      limit: ENV.fetch('API_RATE_LIMIT_WEBHOOK_INGRESS', '600').to_i.clamp(1, 1_000_000),
      window_seconds: WINDOW_SECONDS
    },
    'public_registration' => {
      limit: ENV.fetch('API_RATE_LIMIT_PUBLIC_REGISTRATION', '30').to_i.clamp(1, 1_000_000),
      window_seconds: WINDOW_SECONDS
    },
    'default' => {
      limit: ENV.fetch('API_RATE_LIMIT_DEFAULT', '200').to_i.clamp(1, 1_000_000),
      window_seconds: WINDOW_SECONDS
    }
  }.freeze

  module Catalog
    module_function

    # Returns category key string or nil to skip throttling (should not happen for BaseController children).
    def resolve(controller_path:, action_name:)
      case controller_path
      when 'api/v1/payment_intents'
        case action_name
        when 'create', 'authorize', 'capture', 'void'
          'payment_mutation'
        when 'index', 'show'
          'read'
        else
          'default'
        end
      when 'api/v1/refunds'
        action_name == 'create' ? 'payment_mutation' : 'default'
      when 'api/v1/customers'
        case action_name
        when 'index', 'show'
          'read'
        when 'create'
          'resource_write'
        else
          'default'
        end
      when 'api/v1/payment_methods'
        'resource_write'
      when 'api/v1/merchants'
        action_name == 'me' ? 'auth_account' : 'default'
      when 'api/v1/ai/chat'
        'ai'
      else
        'default'
      end
    end
  end

  def self.for_category(name)
    CATEGORIES[name.to_s] || CATEGORIES['default']
  end
end
