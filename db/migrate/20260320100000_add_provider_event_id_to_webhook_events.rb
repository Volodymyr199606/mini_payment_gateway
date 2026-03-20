# frozen_string_literal: true

class AddProviderEventIdToWebhookEvents < ActiveRecord::Migration[7.2]
  def change
    add_column :webhook_events, :provider_event_id, :string
    add_index :webhook_events, :provider_event_id,
              unique: true,
              where: 'provider_event_id IS NOT NULL',
              name: 'index_webhook_events_on_provider_event_id'
  end
end
