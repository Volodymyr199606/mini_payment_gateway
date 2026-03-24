# frozen_string_literal: true

class AddSkillWorkflowMetadataToAiRequestAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_request_audits, :skill_workflow_metadata, :jsonb
  end
end
