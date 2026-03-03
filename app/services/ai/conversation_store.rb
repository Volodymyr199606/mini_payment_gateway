# frozen_string_literal: true

module Ai
  # Stores and retrieves conversation history per merchant for dashboard AI chat.
  # Used to include prior turns in the LLM prompt for follow-up questions.
  class ConversationStore
    KEEP_PER_MERCHANT = 200

    def append!(merchant_id:, role:, content:, agent: nil)
      AiChatMessage.create!(
        merchant_id: merchant_id,
        role: role.to_s,
        content: content.to_s,
        agent: agent
      )
      prune_old!(merchant_id)
    end

    # Returns last N messages in chronological order: [{ role:, content: }, ...]
    def recent_messages(merchant_id:, limit: 10)
      AiChatMessage
        .where(merchant_id: merchant_id)
        .chronological
        .limit(limit)
        .pluck(:role, :content)
        .map { |role, content| { role: role, content: content } }
    end

    # Keeps only last KEEP_PER_MERCHANT per merchant
    def prune_old!(merchant_id)
      ids_to_keep = AiChatMessage
        .where(merchant_id: merchant_id)
        .recent_first
        .limit(KEEP_PER_MERCHANT)
        .pluck(:id)
      AiChatMessage
        .where(merchant_id: merchant_id)
        .where.not(id: ids_to_keep)
        .delete_all
    end
  end
end
