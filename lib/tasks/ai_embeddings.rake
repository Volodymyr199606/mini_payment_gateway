# frozen_string_literal: true

namespace :ai do
  desc 'Backfill doc_section_embeddings from docs (requires EMBEDDING_API_KEY or OPENAI_API_KEY and pgvector). Set DRY_RUN=1 to use stub embeddings (no API call).'
  task backfill_doc_embeddings: :environment do
    unless DocSectionEmbedding.table_exists?
      puts 'doc_section_embeddings table not found. Install pgvector and run db:migrate.'
      next
    end

    dry_run = ENV['DRY_RUN'].to_s.strip.downcase.in?(%w[1 true yes])
    use_stub = dry_run || (ENV['EMBEDDING_API_KEY'].blank? && ENV['OPENAI_API_KEY'].blank?)
    if use_stub && !dry_run
      puts 'Set EMBEDDING_API_KEY or OPENAI_API_KEY to run backfill (or use DRY_RUN=1 with stub).'
      next
    end

    Ai::Rag::DocsIndex.reset!
    index = Ai::Rag::DocsIndex.instance
    sections = index.sections
    helpers = Ai::Rag::Helpers
    client = use_stub ? nil : Ai::Rag::EmbeddingClient.new

    Rails.logger.info({
      event: 'ai_backfill_start',
      sections_total: sections.size,
      dry_run: dry_run,
      stub_embedding: use_stub
    }.to_json)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    upserts = 0
    failures = 0

    sections.each do |s|
      file = helpers.normalize_file(s[:file])
      anchor = helpers.slugify_heading(s[:heading].to_s)
      section_id = helpers.section_id(file, anchor)
      vec = if use_stub
              Ai::Rag::SmokeHybrid.deterministic_embedding_for(section_id)
            else
              text = "#{s[:heading]}\n#{s[:content]}".to_s.truncate(8000)
              client.embed(text)
            end

      unless vec.is_a?(Array) && vec.size == Ai::Rag::EmbeddingClient::DIMENSIONS
        failures += 1
        Rails.logger.warn({ event: 'ai_backfill_skip', section_id: section_id, reason: 'embed_failed_or_wrong_dims' }.to_json)
        next
      end

      unless dry_run
        vector_literal = "[#{vec.map { |x| Float(x) }.join(',')}]"
        DocSectionEmbedding.connection.execute(
          <<~SQL.squish
            INSERT INTO doc_section_embeddings (section_id, embedding, updated_at)
            VALUES (#{DocSectionEmbedding.connection.quote(section_id)}, '#{vector_literal}'::vector, NOW())
            ON CONFLICT (section_id) DO UPDATE SET embedding = EXCLUDED.embedding, updated_at = NOW()
          SQL
        )
      end
      upserts += 1
      print '.' if (upserts % 10).zero?
    end

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    Rails.logger.info({
      event: 'ai_backfill_finish',
      sections_processed: sections.size,
      upserts: upserts,
      failures: failures,
      duration_ms: duration_ms,
      dry_run: dry_run
    }.to_json)
    puts "\nDone. Upserted #{upserts} embeddings.#{failures.positive? ? " Failures: #{failures}." : ''} (#{duration_ms}ms)"
  end

  desc 'Smoke test hybrid retrieval: pgvector + table check, optional DRY_RUN backfill, one HybridRetriever run'
  task smoke_hybrid: :environment do
    ok = true
    unless Ai::Rag::SmokeHybrid.pgvector_enabled?
      puts 'FAIL: pgvector extension not enabled. Install pgvector and run db:migrate.'
      ok = false
    end
    unless Ai::Rag::SmokeHybrid.doc_section_embeddings_exists?
      puts 'FAIL: doc_section_embeddings table not found. Run db:migrate.'
      ok = false
    end
    unless ok
      puts 'Smoke aborted.'
      next
    end

    puts 'pgvector: ok'
    puts 'doc_section_embeddings: ok'

    if ENV['EMBEDDING_API_KEY'].blank? && ENV['OPENAI_API_KEY'].blank?
      puts 'No embedding API keys; running backfill in DRY_RUN (stub embeddings, no DB writes)...'
      ENV['DRY_RUN'] = '1'
      Rake::Task['ai:backfill_doc_embeddings'].invoke
      ENV.delete('DRY_RUN')
    else
      puts 'Embedding keys set; skipping backfill (run ai:backfill_doc_embeddings if needed).'
    end

    puts 'Running one HybridRetriever retrieval...'
    summary = Ai::Rag::SmokeHybrid.run_smoke_retrieval
    puts "  retriever: #{summary[:retriever]}"
    puts "  sections returned: #{summary[:sections_count]}"
    puts '  first 3 citations:'
    summary[:citations].each_with_index do |c, i|
      puts "    #{i + 1}. #{c[:file]}##{c[:anchor]} — #{c[:heading].to_s.truncate(50)}"
    end
    puts 'Smoke hybrid: done.'
  end
end
