require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

# Load custom middleware (not autoloaded during config)
require_relative "../app/middleware/request_id_middleware"

module MiniPaymentGateway
  class Application < Rails::Application
    config.load_defaults 7.1
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Asset pipeline: include app/javascript for importmap
    config.assets.paths << Rails.root.join("app/javascript")

    # Add request ID middleware
    config.middleware.use RequestIdMiddleware
  end
end
