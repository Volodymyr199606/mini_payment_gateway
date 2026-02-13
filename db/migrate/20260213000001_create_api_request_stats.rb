# frozen_string_literal: true

class CreateApiRequestStats < ActiveRecord::Migration[7.2]
  def change
    create_table :api_request_stats, if_not_exists: true do |t|
      t.references :merchant, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :requests_count, null: false, default: 0
      t.integer :errors_count, null: false, default: 0
      t.integer :rate_limited_count, null: false, default: 0
      t.timestamps
    end

    add_index :api_request_stats, %i[merchant_id date], unique: true, if_not_exists: true
    add_index :api_request_stats, :date, if_not_exists: true
  end
end
