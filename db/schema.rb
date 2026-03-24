# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_03_24_220000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "ai_chat_messages", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.string "agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ai_chat_session_id"
    t.index ["ai_chat_session_id", "created_at"], name: "index_ai_chat_messages_on_ai_chat_session_id_and_created_at"
    t.index ["ai_chat_session_id"], name: "index_ai_chat_messages_on_ai_chat_session_id"
    t.index ["merchant_id", "created_at"], name: "index_ai_chat_messages_on_merchant_id_and_created_at"
    t.index ["merchant_id"], name: "index_ai_chat_messages_on_merchant_id"
  end

  create_table "ai_chat_sessions", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.text "summary_text"
    t.datetime "summary_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "current_topic"
    t.index ["merchant_id"], name: "index_ai_chat_sessions_on_merchant_id"
  end

  create_table "ai_request_audits", force: :cascade do |t|
    t.string "request_id", null: false
    t.string "endpoint", null: false
    t.bigint "merchant_id"
    t.string "agent_key", null: false
    t.string "retriever_key"
    t.string "composition_mode"
    t.boolean "tool_used", default: false, null: false
    t.jsonb "tool_names", default: []
    t.boolean "fallback_used", default: false, null: false
    t.boolean "citation_reask_used", default: false, null: false
    t.boolean "memory_used", default: false, null: false
    t.boolean "summary_used", default: false, null: false
    t.jsonb "parsed_entities", default: {}
    t.jsonb "parsed_intent_hints", default: {}
    t.integer "citations_count", default: 0
    t.integer "retrieved_sections_count"
    t.integer "latency_ms"
    t.string "model_used"
    t.boolean "success", default: true, null: false
    t.string "error_class"
    t.string "error_message"
    t.datetime "created_at", null: false
    t.boolean "followup_detected", default: false, null: false
    t.string "followup_type"
    t.boolean "authorization_denied", default: false, null: false
    t.string "policy_reason_code"
    t.boolean "tool_blocked_by_policy", default: false, null: false
    t.boolean "followup_inheritance_blocked", default: false, null: false
    t.string "corpus_version"
    t.boolean "deterministic_explanation_used", default: false, null: false
    t.string "explanation_type"
    t.string "explanation_key"
    t.jsonb "invoked_skills", default: [], null: false
    t.jsonb "skill_workflow_metadata"
    t.index ["agent_key"], name: "index_ai_request_audits_on_agent_key"
    t.index ["created_at"], name: "index_ai_request_audits_on_created_at"
    t.index ["merchant_id"], name: "index_ai_request_audits_on_merchant_id"
    t.index ["request_id"], name: "index_ai_request_audits_on_request_id"
    t.index ["success"], name: "index_ai_request_audits_on_success"
  end

  create_table "api_request_stats", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.date "date", null: false
    t.integer "requests_count", default: 0, null: false
    t.integer "errors_count", default: 0, null: false
    t.integer "rate_limited_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_api_request_stats_on_date"
    t.index ["merchant_id", "date"], name: "index_api_request_stats_on_merchant_id_and_date", unique: true
    t.index ["merchant_id"], name: "index_api_request_stats_on_merchant_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "merchant_id"
    t.string "actor_type", null: false
    t.string "actor_id"
    t.string "action", null: false
    t.string "auditable_type"
    t.string "auditable_id"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_type", "actor_id"], name: "index_audit_logs_on_actor_type_and_actor_id"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["merchant_id"], name: "index_audit_logs_on_merchant_id"
  end

  create_table "customers", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.string "email", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_id", "email"], name: "index_customers_on_merchant_id_and_email"
    t.index ["merchant_id"], name: "index_customers_on_merchant_id"
  end

  create_table "doc_section_embeddings", primary_key: "section_id", id: :string, force: :cascade do |t|
    t.datetime "updated_at", null: false
    t.index ["section_id"], name: "index_doc_section_embeddings_on_section_id", unique: true
  end

  create_table "idempotency_records", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.string "idempotency_key", null: false
    t.string "endpoint", null: false
    t.string "request_hash", null: false
    t.jsonb "response_body", null: false
    t.integer "status_code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_id", "idempotency_key", "endpoint"], name: "index_idempotency_on_merchant_key_endpoint", unique: true
    t.index ["merchant_id"], name: "index_idempotency_records_on_merchant_id"
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.bigint "transaction_id"
    t.string "entry_type", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "USD", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entry_type"], name: "index_ledger_entries_on_entry_type"
    t.index ["merchant_id"], name: "index_ledger_entries_on_merchant_id"
    t.index ["transaction_id"], name: "index_ledger_entries_on_transaction_id"
  end

  create_table "merchants", force: :cascade do |t|
    t.string "name", null: false
    t.string "api_key_digest", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email"
    t.string "password_digest"
    t.index ["api_key_digest"], name: "index_merchants_on_api_key_digest", unique: true
    t.index ["email"], name: "index_merchants_on_email", unique: true, where: "((email IS NOT NULL) AND ((email)::text <> ''::text))"
    t.index ["status"], name: "index_merchants_on_status"
  end

  create_table "payment_intents", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.bigint "customer_id", null: false
    t.bigint "payment_method_id"
    t.integer "amount_cents", null: false
    t.string "currency", default: "USD", null: false
    t.string "status", default: "created", null: false
    t.string "idempotency_key"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "dispute_status", default: "none", null: false
    t.index ["customer_id"], name: "index_payment_intents_on_customer_id"
    t.index ["merchant_id", "idempotency_key"], name: "index_payment_intents_on_merchant_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["merchant_id"], name: "index_payment_intents_on_merchant_id"
    t.index ["payment_method_id"], name: "index_payment_intents_on_payment_method_id"
    t.index ["status"], name: "index_payment_intents_on_status"
  end

  create_table "payment_methods", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "method_type", null: false
    t.string "last4"
    t.string "brand"
    t.integer "exp_month"
    t.integer "exp_year"
    t.string "token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_payment_methods_on_customer_id"
    t.index ["token"], name: "index_payment_methods_on_token", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "payment_intent_id", null: false
    t.string "kind", null: false
    t.string "status", null: false
    t.integer "amount_cents", null: false
    t.string "processor_ref"
    t.string "failure_code"
    t.string "failure_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_transactions_on_kind"
    t.index ["payment_intent_id"], name: "index_transactions_on_payment_intent_id"
    t.index ["processor_ref"], name: "index_transactions_on_processor_ref"
    t.index ["status"], name: "index_transactions_on_status"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.bigint "merchant_id"
    t.string "event_type", null: false
    t.jsonb "payload", null: false
    t.string "signature"
    t.datetime "delivered_at"
    t.string "delivery_status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider_event_id"
    t.index ["delivery_status"], name: "index_webhook_events_on_delivery_status"
    t.index ["event_type"], name: "index_webhook_events_on_event_type"
    t.index ["merchant_id"], name: "index_webhook_events_on_merchant_id"
    t.index ["provider_event_id"], name: "index_webhook_events_on_provider_event_id", unique: true, where: "(provider_event_id IS NOT NULL)"
  end

  add_foreign_key "ai_chat_messages", "ai_chat_sessions"
  add_foreign_key "ai_chat_messages", "merchants"
  add_foreign_key "ai_chat_sessions", "merchants"
  add_foreign_key "ai_request_audits", "merchants"
  add_foreign_key "api_request_stats", "merchants"
  add_foreign_key "audit_logs", "merchants"
  add_foreign_key "customers", "merchants"
  add_foreign_key "idempotency_records", "merchants"
  add_foreign_key "ledger_entries", "merchants"
  add_foreign_key "ledger_entries", "transactions"
  add_foreign_key "payment_intents", "customers"
  add_foreign_key "payment_intents", "merchants"
  add_foreign_key "payment_intents", "payment_methods"
  add_foreign_key "payment_methods", "customers"
  add_foreign_key "transactions", "payment_intents"
  add_foreign_key "webhook_events", "merchants"
end
