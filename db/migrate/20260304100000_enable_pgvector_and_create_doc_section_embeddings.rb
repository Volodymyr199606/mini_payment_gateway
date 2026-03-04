# frozen_string_literal: true

# Requires pgvector extension. Install on PostgreSQL first, then run db:migrate.
# See https://github.com/pgvector/pgvector#installation
class EnablePgvectorAndCreateDocSectionEmbeddings < ActiveRecord::Migration[7.2]
  def change
    enable_extension 'vector' unless extension_enabled?('vector')

    create_table :doc_section_embeddings, id: false do |t|
      t.string :section_id, null: false
      t.datetime :updated_at, null: false
    end

    add_index :doc_section_embeddings, :section_id, unique: true
    execute 'ALTER TABLE doc_section_embeddings ADD PRIMARY KEY (section_id)'

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
end
