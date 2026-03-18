# frozen_string_literal: true

module Ai
  module Async
    # Enqueues conversation summary refresh with duplicate suppression.
    # Call after a successful AI response; job runs ConversationSummarizer in background.
    class SummaryRefreshEnqueuer
      CACHE_KEY_PREFIX = 'ai:summary_queued'
      CACHE_TTL = 60 # seconds; avoid duplicate enqueues for same session
      MEMORY_CACHE = ActiveSupport::Cache.lookup_store(:memory_store)

      def self.enqueue_if_ok(ai_chat_session_id:, merchant_id: nil, request_id: nil)
        new(ai_chat_session_id: ai_chat_session_id, merchant_id: merchant_id, request_id: request_id).enqueue_if_ok
      end

      def initialize(ai_chat_session_id:, merchant_id: nil, request_id: nil)
        @ai_chat_session_id = ai_chat_session_id
        @merchant_id = merchant_id
        @request_id = request_id
      end

      def enqueue_if_ok
        return false if @ai_chat_session_id.blank?
        return false if recently_queued?

        cache_store.write(cache_key, true, expires_in: CACHE_TTL.seconds)
        Ai::RefreshConversationSummaryJob.perform_later(@ai_chat_session_id)
        Ai::BaseJob.log_enqueued(
          job_class: 'Ai::RefreshConversationSummaryJob',
          ai_chat_session_id: @ai_chat_session_id,
          merchant_id: @merchant_id,
          request_id: @request_id
        )
        true
      end

      private

      def recently_queued?
        cache_store.read(cache_key).present?
      end

      def cache_key
        "#{CACHE_KEY_PREFIX}:#{@ai_chat_session_id}"
      end

      def cache_store
        # In test, Rails.cache defaults to :null_store which doesn't persist.
        # Use a tiny in-process memory store so duplicate suppression works in specs.
        if Rails.cache.class.name.include?('NullStore')
          MEMORY_CACHE
        else
          Rails.cache
        end
      end
    end
  end
end
