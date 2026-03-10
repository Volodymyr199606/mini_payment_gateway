# frozen_string_literal: true

namespace :ai do
  desc 'Run AI eval harness (golden questions). Exit non-zero if any failures. Stub Groq/Ledger in tests.'
  task evals: :environment do
    merchant_id = ENV['EVAL_MERCHANT_ID'].presence
    unless merchant_id
      merchant = Merchant.order(:id).first if defined?(Merchant)
      merchant_id = merchant&.id
    end
    merchant_id = merchant_id.to_i
    if merchant_id.zero?
      puts 'No merchant found. Set EVAL_MERCHANT_ID or ensure a Merchant exists (e.g. db:seed).'
      exit 1
    end

    path = ENV['EVAL_FIXTURE_PATH'].presence || Rails.root.join('spec/fixtures/ai/golden_questions.yml')
    path = Pathname(path) unless path.is_a?(Pathname)
    unless path.exist?
      puts "Eval fixture not found: #{path}"
      exit 1
    end

    cases = Ai::Evals::Runner.load_questions(path)
    if cases.empty?
      puts 'No eval cases loaded.'
      exit 0
    end

    results = Ai::Evals::Runner.run_all(merchant_id: merchant_id, path: path)
    summary = Ai::Evals::Runner.print_summary(results)
    exit summary[:failed].positive? ? 1 : 0
  end
end
