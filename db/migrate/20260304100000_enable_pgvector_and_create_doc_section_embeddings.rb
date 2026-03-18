# frozen_string_literal: true

# Uses pgvector extension when available. If not installed (e.g. Windows PostgreSQL without
# pgvector), the table is created without the embedding column so migrations can complete.
# See https://github.com/pgvector/pgvector#installation
class EnablePgvectorAndCreateDocSectionEmbeddings < ActiveRecord::Migration[7.2]
  def change
    vector_available = enable_vector_extension_if_available

    create_table :doc_section_embeddings, id: false do |t|
      t.string :section_id, null: false
      t.datetime :updated_at, null: false
    end

    add_index :doc_section_embeddings, :section_id, unique: true
    execute 'ALTER TABLE doc_section_embeddings ADD PRIMARY KEY (section_id)'

    return unless vector_available

    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          ALTER TABLE doc_section_embeddings
          ADD COLUMN embedding vector(1536) NOT NULL
        SQL
        execute <<-SQL.squish
          CREATE INDEX index_doc_section_embeddings_on_embedding_cosine
          ON doc_section_embeddings USING hnsw (embedding vector_cosine_ops)
        SQL
      end
      dir.down do
        remove_column :doc_section_embeddings, :embedding
      end
    end
  end

  private

  # Check availability without raising (avoid PG::InFailedSqlTransaction).
  def enable_vector_extension_if_available
    return true if extension_enabled?('vector')

    available = connection.select_value(
      "SELECT 1 FROM pg_available_extensions WHERE name = 'vector'"
    )
    unless available
      Rails.logger&.warn '[pgvector] Extension not available; doc_section_embeddings will have no embedding column. Install pgvector to enable RAG.'
      return false
    end

    enable_extension 'vector'
    true
  end
end
