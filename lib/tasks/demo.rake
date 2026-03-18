# frozen_string_literal: true

namespace :demo do
  desc 'Reset and seed demo data (development only). Prints credentials and notable IDs.'
  task reset: :environment do
    abort 'Demo seed is for development only.' if Rails.env.production?

    require_relative '../../db/seeds/demo'
    api_keys = {}
    Seeds::Demo.run(api_keys: api_keys)
    summary = Seeds::Demo.summary

    puts "\n✅ Demo data seeded.\n"
    puts "\n--- Demo merchant (dashboard) ---"
    puts "  Email:    #{summary[:demo_email]}"
    puts "  Password: #{summary[:demo_password]}"
    puts "  API key:  #{summary[:demo_api_key]}"
    puts "\n--- Notable IDs (use in API / AI prompts) ---"
    puts "  Payment intent (created):   #{summary[:payment_intent_created]}"
    puts "  Payment intent (authorized/requires_capture): #{summary[:payment_intent_authorized]}"
    puts "  Payment intent (captured): #{summary[:payment_intent_captured]}"
    puts "  Payment intent (refunded): #{summary[:payment_intent_refunded]}"
    puts "  Payment intent (failed):   #{summary[:payment_intent_failed]}"
    puts "  Payment intent (canceled): #{summary[:payment_intent_canceled]}"
    puts "  Transaction (capture):      #{summary[:transaction_capture]}"
    puts "  Transaction (refund):       #{summary[:transaction_refund]}"
    puts "  Webhook (succeeded):        #{summary[:webhook_succeeded]}"
    puts "  Webhook (failed):           #{summary[:webhook_failed]}"
    puts "  Webhook (pending):         #{summary[:webhook_pending]}"
    puts "\n--- Scoping merchant (multi-tenant demos) ---"
    puts "  Email: #{summary[:scoping_email]}  Password: #{summary[:scoping_password]}"
    puts "\n--- Suggested prompts ---"
    puts "  \"What is the status of payment intent #{summary[:payment_intent_authorized]}?\""
    puts "  \"What is my net volume for the last 7 days?\""
    puts "  \"What happened to webhook #{summary[:webhook_failed]}?\""
    puts "  \"What does requires_capture mean?\""
    puts "  \"Show me failed captures this week\""
    puts "  \"What about yesterday?\""

    if Rails.root.join('tmp').exist?
      path = Rails.root.join('tmp', 'demo_summary.txt')
      File.write(path, <<~TEXT)
        Demo merchant: #{summary[:demo_email]} / #{summary[:demo_password]}
        API key: #{summary[:demo_api_key]}
        Payment intents: created=#{summary[:payment_intent_created]} authorized=#{summary[:payment_intent_authorized]} captured=#{summary[:payment_intent_captured]} refunded=#{summary[:payment_intent_refunded]} failed=#{summary[:payment_intent_failed]} canceled=#{summary[:payment_intent_canceled]}
        Transactions: capture=#{summary[:transaction_capture]} refund=#{summary[:transaction_refund]}
        Webhooks: succeeded=#{summary[:webhook_succeeded]} failed=#{summary[:webhook_failed]} pending=#{summary[:webhook_pending]}
        Scoping merchant: #{summary[:scoping_email]} / #{summary[:scoping_password]}
      TEXT
      puts "\nSummary written to #{path}"
    end
  end

  desc 'Alias for demo:reset (one-command demo setup)'
  task seed: :environment do
    Rake::Task['demo:reset'].invoke
  end
end
