# frozen_string_literal: true

module Ai
  module Performance
    # Cache wrapper for ConversationContextBuilder output.
    # Invalidates when message count changes (new message added).
    class CachedConversationContextBuilder
      def self.call(ai_chat_session, max_turns: 8)
        return ::Ai::ConversationContextBuilder.call(ai_chat_session, max_turns: max_turns) unless ai_chat_session

        session_id = ai_chat_session.id
        messages_count = ai_chat_session.ai_chat_messages.count
        key = CacheKeys.memory(session_id: session_id, messages_count: messages_count)
        bypass = CachePolicy.bypass?

        result = CacheFetcher.fetch(key: key, category: :memory, bypass: bypass) do
          ctx = ::Ai::ConversationContextBuilder.call(ai_chat_session, max_turns: max_turns)
          ctx.transform_keys(&:to_s)
        end

        result&.transform_keys(&:to_sym) || ::Ai::ConversationContextBuilder.call(ai_chat_session, max_turns: max_turns)
      end
    end
  end
end
