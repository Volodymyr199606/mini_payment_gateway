# frozen_string_literal: true

class AddFollowupToAiRequestAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_request_audits, :followup_detected, :boolean, default: false, null: false
    add_column :ai_request_audits, :followup_type, :string
  end
end
