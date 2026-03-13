# frozen_string_literal: true

class AddPolicyToAiRequestAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_request_audits, :authorization_denied, :boolean, default: false, null: false
    add_column :ai_request_audits, :policy_reason_code, :string
    add_column :ai_request_audits, :tool_blocked_by_policy, :boolean, default: false, null: false
    add_column :ai_request_audits, :followup_inheritance_blocked, :boolean, default: false, null: false
  end
end
