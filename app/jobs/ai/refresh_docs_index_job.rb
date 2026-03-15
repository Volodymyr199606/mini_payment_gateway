# frozen_string_literal: true

module Ai
  # Refreshes the in-memory docs index (DocsIndex). Safe to run after doc changes.
  # No embeddings/vector; only resets the keyword index used by RetrievalService.
  class RefreshDocsIndexJob < Ai::BaseJob
    queue_as :default

    def perform
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ::Ai::Rag::DocsIndex.reset!
      ::Ai::Rag::DocsIndex.instance
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      self.class.log_performed(
        job_class: self.class.name,
        duration_ms: duration_ms
      )
    rescue StandardError => e
      self.class.log_failed(
        job_class: self.class.name,
        error_class: e.class.name,
        error_message: e.message
      )
      raise
    end
  end
end
