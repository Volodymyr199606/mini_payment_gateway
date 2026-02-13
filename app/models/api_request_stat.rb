# frozen_string_literal: true

# Daily counters for API request metrics (merchant-scoped).
# Used for dashboard "API Health (last 24h)" only. Updates must never affect API responses.
class ApiRequestStat < ApplicationRecord
  belongs_to :merchant

  validates :date, presence: true
  validates :requests_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :errors_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :rate_limited_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :date, uniqueness: { scope: :merchant_id }

  # Atomic upsert: increment today's counters. Swallow all errors.
  def self.record_request!(merchant_id:, is_error: false, is_rate_limited: false)
    return if merchant_id.blank?

    err = is_error ? 1 : 0
    rl = is_rate_limited ? 1 : 0
    sql = <<~SQL.squish
      INSERT INTO api_request_stats (merchant_id, date, requests_count, errors_count, rate_limited_count, created_at, updated_at)
      VALUES (?, CURRENT_DATE, 1, ?, ?, now(), now())
      ON CONFLICT (merchant_id, date) DO UPDATE SET
        requests_count = api_request_stats.requests_count + 1,
        errors_count = api_request_stats.errors_count + EXCLUDED.errors_count,
        rate_limited_count = api_request_stats.rate_limited_count + EXCLUDED.rate_limited_count,
        updated_at = now()
    SQL
    connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, merchant_id, err, rl]))
  rescue StandardError
    # Must never affect API responses
  end
end
