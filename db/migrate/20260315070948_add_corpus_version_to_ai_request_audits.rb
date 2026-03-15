class AddCorpusVersionToAiRequestAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_request_audits, :corpus_version, :string
  end
end
