# frozen_string_literal: true

# Stores one embedding vector per doc section for vector similarity search.
# section_id format: "docs/PAYMENT_LIFECYCLE.md#authorize-in-this-project"
# Backfill via: rake ai:backfill_doc_embeddings
# When pgvector is not installed, the embedding column may be absent; vector search is then no-op.
class DocSectionEmbedding < ApplicationRecord
  self.primary_key = :section_id

  validates :section_id, presence: true, uniqueness: true
  validates :embedding, presence: true, if: :embedding_column?

  # Returns array of [section_id, distance] ordered by cosine distance (asc = more similar).
  # query_embedding: array of floats (length 1536). Returns [] if table, extension, or column missing.
  def self.nearest(query_embedding, limit: 6)
    return [] unless table_exists?
    return [] unless embedding_column?
    return [] if query_embedding.blank? || query_embedding.size != 1536

    vec = query_embedding.map { |x| Float(x) }.join(',')
    vector_literal = "[#{vec}]"
    limit_i = limit.to_i
    sql = "SELECT section_id, (embedding <=> '#{vector_literal}'::vector) AS distance FROM doc_section_embeddings ORDER BY embedding <=> '#{vector_literal}'::vector LIMIT #{limit_i}"
    connection.select_all(sql).to_a.map { |row| [row['section_id'], row['distance'].to_f] }
  end

  def self.embedding_column?
    table_exists? && column_names.include?('embedding')
  end

  private

  def embedding_column?
    self.class.embedding_column?
  end
end
