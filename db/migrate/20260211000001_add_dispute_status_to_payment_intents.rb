# frozen_string_literal: true

class AddDisputeStatusToPaymentIntents < ActiveRecord::Migration[7.2]
  def change
    add_column :payment_intents, :dispute_status, :string, default: 'none', null: false
  end
end
