# frozen_string_literal: true

module MiniPaymentGatewayPerf
  # One lambda per scenario name in Runner::GROUPS. Each returns a row hash for Report (without :scenario).
  module Scenarios
    module_function

    PERF_RETRIEVAL_MESSAGE = 'Explain how payment captures and refunds work for merchants on this platform.'
    PERF_TOOL_MESSAGE = 'What are my account details and merchant summary?'

    def webhook_payload(merchant_id:, event_id:)
      h = {
        'event_type' => 'transaction.succeeded',
        'id' => event_id,
        'data' => { 'merchant_id' => merchant_id }
      }
      body = JSON.generate(h)
      sig = WebhookSignatureService.generate_signature(body, Rails.application.config.webhook_secret)
      [body, sig]
    end

    def registry
      @registry ||= {
        'payment_create_intent' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'POST /api/v1/payment_intents (simulated processor)',
            cache_state: nil
          ) do |h, w|
            st = h.api_post(
              '/api/v1/payment_intents',
              w,
              {
                payment_intent: {
                  customer_id: w.customer.id,
                  payment_method_id: w.payment_method.id,
                  amount_cents: 5000,
                  currency: 'USD'
                }
              }
            )
            raise "expected 201, got #{st}" unless st == 201
          end
        end,

        'payment_authorize' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'create PI + POST authorize',
            cache_state: nil
          ) do |h, w|
            st = h.api_post(
              '/api/v1/payment_intents',
              w,
              {
                payment_intent: {
                  customer_id: w.customer.id,
                  payment_method_id: w.payment_method.id,
                  amount_cents: 5000,
                  currency: 'USD'
                }
              }
            )
            raise "create failed #{st}" unless st == 201

            pid = h.response_json['data']['id']
            st = h.api_post("/api/v1/payment_intents/#{pid}/authorize", w, {})
            raise "authorize failed #{st}" unless st == 200
          end
        end,

        'payment_capture' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'create + authorize + POST capture',
            cache_state: nil
          ) do |h, w|
            st = h.api_post(
              '/api/v1/payment_intents',
              w,
              {
                payment_intent: {
                  customer_id: w.customer.id,
                  payment_method_id: w.payment_method.id,
                  amount_cents: 5000,
                  currency: 'USD'
                }
              }
            )
            raise "create failed #{st}" unless st == 201

            pid = h.response_json['data']['id']
            st = h.api_post("/api/v1/payment_intents/#{pid}/authorize", w, {})
            raise "authorize failed #{st}" unless st == 200

            st = h.api_post("/api/v1/payment_intents/#{pid}/capture", w, {})
            raise "capture failed #{st}" unless st == 200
          end
        end,

        'payment_refund_partial' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'captured PI + POST refunds partial',
            cache_state: nil
          ) do |h, w|
            pi = w.create_captured_intent!
            st = h.api_post(
              "/api/v1/payment_intents/#{pi.id}/refunds",
              w,
              { refund: { amount_cents: 1000 } }
            )
            raise "refund failed #{st}" unless st == 201
          end
        end,

        'payment_list_intents' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            prepare: ->(_h, w) { w.seed_for_list_endpoints! },
            notes: 'GET /api/v1/payment_intents (seeded merchant lists)',
            cache_state: 'list_index'
          ) do |h, w|
            st = h.api_get('/api/v1/payment_intents', w)
            raise "list intents failed #{st}" unless st == 200
          end
        end,

        'payment_list_transactions' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            prepare: lambda do |h, w|
              w.seed_for_list_endpoints!
              h.dashboard_sign_in!(email: w.email, password: w.password)
            end,
            notes: 'GET /dashboard/transactions (session + index)',
            cache_state: 'list_index'
          ) do |h, _w|
            st = h.dashboard_get('/dashboard/transactions')
            raise "transactions index failed #{st}" unless st == 200
          end
        end,

        'payment_list_ledger' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            prepare: lambda do |h, w|
              w.seed_for_list_endpoints!
              h.dashboard_sign_in!(email: w.email, password: w.password)
            end,
            notes: 'GET /dashboard/ledger',
            cache_state: 'list_index'
          ) do |h, _w|
            st = h.dashboard_get('/dashboard/ledger')
            raise "ledger index failed #{st}" unless st == 200
          end
        end,

        'payment_authorize_idempotent_warm' => lambda do |iterations:, concurrency:|
          latencies = []
          errors = 0
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          iterations.times do
            h = Harness.new
            w = World.build!
            st = h.api_post(
              '/api/v1/payment_intents',
              w,
              {
                payment_intent: {
                  customer_id: w.customer.id,
                  payment_method_id: w.payment_method.id,
                  amount_cents: 5000,
                  currency: 'USD'
                }
              }
            )
            unless st == 201
              errors += 1
              next
            end

            pid = h.response_json['data']['id']
            key = "perf-auth-#{SecureRandom.hex(8)}"
            st = h.api_post("/api/v1/payment_intents/#{pid}/authorize", w, { idempotency_key: key })
            unless st == 200
              errors += 1
              next
            end

            ms, err = Runner.timed_ms do
              st2 = h.api_post("/api/v1/payment_intents/#{pid}/authorize", w, { idempotency_key: key })
              raise "idempotent authorize failed #{st2}" unless st2 == 200
            end
            if err
              errors += 1
            else
              latencies << ms
            end
          end
          t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          summary = Metrics.summarize(latencies)
          Metrics.merge_timing(summary, errors: errors, duration_sec: t1 - t0).merge(
            cache_state: 'idempotency_hit',
            notes: 'second POST authorize same idempotency_key (cached response)'
          )
        end,

        'webhook_inbound_signed' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'POST /api/v1/webhooks/processor verify+HMAC+persist',
            cache_state: nil
          ) do |h, w|
            body, sig = webhook_payload(merchant_id: w.merchant.id, event_id: "evt_perf_#{SecureRandom.hex(8)}")
            st = h.post_webhook_raw(body, sig)
            raise "webhook failed #{st}" unless st == 201
          end
        end,

        'webhook_inbound_duplicate' => lambda do |iterations:, concurrency:|
          fixed_id = 'evt_perf_duplicate_payload'
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'identical payload replay (each persists; no dedup)',
            cache_state: 'replay'
          ) do |h, w|
            body, sig = webhook_payload(merchant_id: w.merchant.id, event_id: fixed_id)
            st = h.post_webhook_raw(body, sig)
            raise "webhook failed #{st}" unless st == 201
          end
        end,

        'ai_api_chat_operational' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'POST /api/v1/ai/chat retrieval+agent (Groq stubbed)',
            cache_state: nil
          ) do |h, w|
            st = h.api_post('/api/v1/ai/chat', w, { message: PERF_RETRIEVAL_MESSAGE })
            raise "ai chat failed #{st}" unless st == 200
          end
        end,

        'ai_api_chat_same_message_cold_warm' => lambda do |iterations:, concurrency:|
          # Split: half forced cache miss (clear retrieval keys via full cache clear — dev/test safe for perf),
          # half warm hits on same fixed message.
          n_cold = (iterations / 2.0).ceil
          n_warm = iterations - n_cold
          cold_lat = []
          warm_lat = []
          errors = 0
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          h = Harness.new
          w = World.build!
          msg = PERF_RETRIEVAL_MESSAGE

          n_cold.times do
            Rails.cache.clear
            ms, err = Runner.timed_ms do
              st = h.api_post('/api/v1/ai/chat', w, { message: msg })
              raise "ai chat failed #{st}" unless st == 200
            end
            if err
              errors += 1
            else
              cold_lat << ms
            end
          end

          n_warm.times do
            ms, err = Runner.timed_ms do
              st = h.api_post('/api/v1/ai/chat', w, { message: msg })
              raise "ai chat failed #{st}" unless st == 200
            end
            if err
              errors += 1
            else
              warm_lat << ms
            end
          end

          t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          warm_summary = Metrics.summarize(warm_lat)
          cold_summary = Metrics.summarize(cold_lat)
          combined = cold_lat + warm_lat
          overall = Metrics.summarize(combined)
          merged = Metrics.merge_timing(overall, errors: errors, duration_sec: t1 - t0)
          merged.merge(
            cache_state: 'cold_then_warm',
            notes: "cold_med=#{cold_summary[:median_ms]} cold_p95=#{cold_summary[:p95_ms]} warm_med=#{warm_summary[:median_ms]} warm_p95=#{warm_summary[:p95_ms]} runs_cold=#{cold_lat.size} runs_warm=#{warm_lat.size}"
          )
        end,

        'ai_dashboard_tool_orchestration' => lambda do |iterations:, concurrency:|
          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'dashboard AI chat tool/orchestration path (Groq stubbed)',
            cache_state: nil
          ) do |h, w|
            st = h.dashboard_ai_chat!(w, message: PERF_TOOL_MESSAGE)
            raise "dashboard ai failed #{st}" unless st == 200
          end
        end,

        'dev_ai_health_json' => lambda do |iterations:, concurrency:|
          unless Rails.env.development? || Rails.env.test?
            return {
              runs: 0,
              errors: 1,
              min_ms: nil,
              max_ms: nil,
              mean_ms: nil,
              median_ms: nil,
              p95_ms: nil,
              duration_sec: 0,
              throughput_rps: nil,
              cache_state: nil,
              notes: 'skipped: dev routes only in development/test'
            }
          end

          Runner.measure(
            iterations: iterations,
            concurrency: concurrency,
            notes: 'GET /dev/ai_health.json internal health reporter',
            cache_state: nil
          ) do |h, _w|
            h.session.get('/dev/ai_health', headers: { 'Accept' => 'application/json' })
            st = h.session.response.status
            raise "dev ai health failed #{st}" unless st == 200
          end
        end
      }
    end
  end
end
