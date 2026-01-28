require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module MiniPaymentGateway
  class Application < Rails::Application
    config.load_defaults 7.1
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc
    
    # Add request ID middleware
    config.middleware.use RequestIdMiddleware
  end
end
