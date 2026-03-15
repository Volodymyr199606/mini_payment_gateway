# frozen_string_literal: true

module Ai
  # Base for AI background jobs. Adds observability; keeps critical path synchronous.
  #
  # Sync (on-request): auth, rate limit, intent resolution, RequestPlanner, deterministic
  # tools, retrieval for current answer, final response composition.
  # Async (offloaded): conversation summary refresh, analytics rollups, optional cache
  # warm/invalidation, optional doc index refresh, post-stream cleanup triggers.
  class BaseJob < ApplicationJob
    queue_as :default

    class << self
      def log_enqueued(job_class:, **meta)
        ::Ai::Observability::EventLogger.log_ai_job(
          phase: 'enqueued',
          job_class: job_class,
          **meta
        )
      end

      def log_performed(job_class:, duration_ms: nil, **meta)
        ::Ai::Observability::EventLogger.log_ai_job(
          phase: 'performed',
          job_class: job_class,
          duration_ms: duration_ms,
          **meta
        )
      end

      def log_failed(job_class:, error_class: nil, error_message: nil, **meta)
        ::Ai::Observability::EventLogger.log_ai_job(
          phase: 'failed',
          job_class: job_class,
          error_class: error_class,
          error_message: error_message,
          **meta
        )
      end
    end
  end
end
