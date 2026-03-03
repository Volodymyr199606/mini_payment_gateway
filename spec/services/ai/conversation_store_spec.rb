# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ConversationStore do
  include ApiHelpers
  let(:merchant) { create_merchant_with_api_key.first }
  let(:store) { described_class.new }

  describe '#append! and #recent_messages' do
    it 'stores and retrieves messages in chronological order' do
      store.append!(merchant_id: merchant.id, role: 'user', content: 'First question')
      store.append!(merchant_id: merchant.id, role: 'assistant', content: 'First reply', agent: 'support_faq')
      store.append!(merchant_id: merchant.id, role: 'user', content: 'Follow-up')

      recent = store.recent_messages(merchant_id: merchant.id, limit: 10)
      expect(recent.size).to eq(3)
      expect(recent[0][:role]).to eq('user')
      expect(recent[0][:content]).to eq('First question')
      expect(recent[1][:role]).to eq('assistant')
      expect(recent[1][:content]).to eq('First reply')
      expect(recent[2][:role]).to eq('user')
      expect(recent[2][:content]).to eq('Follow-up')
    end

    it 'limits returned messages to specified limit' do
      5.times do |i|
        store.append!(merchant_id: merchant.id, role: 'user', content: "Msg #{i}")
        store.append!(merchant_id: merchant.id, role: 'assistant', content: "Reply #{i}")
      end

      recent = store.recent_messages(merchant_id: merchant.id, limit: 3)
      expect(recent.size).to eq(3)
      expect(recent.map { |m| m[:content] }).to eq(['Msg 0', 'Reply 0', 'Msg 1'])
    end

    it 'is merchant-scoped' do
      other = create_merchant_with_api_key.first
      store.append!(merchant_id: merchant.id, role: 'user', content: 'M1')
      store.append!(merchant_id: other.id, role: 'user', content: 'M2')

      expect(store.recent_messages(merchant_id: merchant.id, limit: 10).map { |m| m[:content] }).to eq(['M1'])
      expect(store.recent_messages(merchant_id: other.id, limit: 10).map { |m| m[:content] }).to eq(['M2'])
    end
  end

  describe '#prune_old!' do
    it 'keeps only last KEEP_PER_MERCHANT messages' do
      (Ai::ConversationStore::KEEP_PER_MERCHANT + 10).times do |i|
        store.append!(merchant_id: merchant.id, role: 'user', content: "Msg #{i}")
      end

      expect(AiChatMessage.where(merchant_id: merchant.id).count).to eq(Ai::ConversationStore::KEEP_PER_MERCHANT)
    end
  end
end
