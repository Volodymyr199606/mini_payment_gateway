# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = ENV['CI'].present?
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.hour.to_i}"
  }
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = true
  config.cache_store = :null_store
  config.action_dispatch.show_exceptions = false
  config.action_controller.allow_forgery_protection = true
  config.active_storage.service = :test
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :test
  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []
  config.active_record.maintain_test_schema = false
  config.active_job.queue_adapter = :test
end
