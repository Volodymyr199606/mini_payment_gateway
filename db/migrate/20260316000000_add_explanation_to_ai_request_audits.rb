# frozen_string_literal: true

class AddExplanationToAiRequestAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_request_audits, :deterministic_explanation_used, :boolean, default: false, null: false
    add_column :ai_request_audits, :explanation_type, :string
    add_column :ai_request_audits, :explanation_key, :string
  end
end
