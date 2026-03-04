# frozen_string_literal: true

namespace :ai do
  desc 'Backfill doc_section_embeddings from docs (requires EMBEDDING_API_KEY or OPENAI_API_KEY and pgvector)'
  task backfill_doc_embeddings: :environment do
    unless DocSectionEmbedding.table_exists?
      puts 'doc_section_embeddings table not found. Install pgvector and run db:migrate.'
      next
    end
    client = Ai::Rag::EmbeddingClient.new
    if ENV['EMBEDDING_API_KEY'].blank? && ENV['OPENAI_API_KEY'].blank?
      puts 'Set EMBEDDING_API_KEY or OPENAI_API_KEY to run backfill.'
      next
    end

    Ai::Rag::DocsIndex.reset!
    Ai::Rag::ContextGraph.reset!
    graph = Ai::Rag::ContextGraph.instance
    nodes = graph.nodes
    puts "Backfilling embeddings for #{nodes.size} sections..."

    count = 0
    nodes.each do |node|
      section_id = node[:id]
      text = "#{node[:heading]}\n#{node[:content]}".to_s.truncate(8000)
      vec = client.embed(text)
      unless vec.is_a?(Array) && vec.size == Ai::Rag::EmbeddingClient::DIMENSIONS
        puts "  skip #{section_id}: embed failed or wrong dimensions"
        next
      end

      vector_literal = "[#{vec.map { |x| Float(x) }.join(',')}]"
      DocSectionEmbedding.connection.execute(
        <<~SQL.squish
          INSERT INTO doc_section_embeddings (section_id, embedding, updated_at)
          VALUES (#{DocSectionEmbedding.connection.quote(section_id)}, '#{vector_literal}'::vector, NOW())
          ON CONFLICT (section_id) DO UPDATE SET embedding = EXCLUDED.embedding, updated_at = NOW()
        SQL
      )
      count += 1
      print '.' if (count % 10).zero?
    end

    puts "\nDone. Upserted #{count} embeddings."
  end
end
