# frozen_string_literal: true

class AddInvokedSkillsToAiRequestAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_request_audits, :invoked_skills, :jsonb, default: [], null: false
  end
end
