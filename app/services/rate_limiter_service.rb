# frozen_string_literal: true

# Fixed-window request counter backed by Rails.cache.
# Cache key includes a time bucket so the window does not "slide" on every write.
class RateLimiterService < BaseService
  def initialize(cache_key_prefix:, limit:, window_seconds:)
    super()
    @cache_key_prefix = cache_key_prefix.to_s
    @limit = limit.to_i
    @window_seconds = window_seconds.to_i
  end

  def call
    if @limit <= 0 || @window_seconds <= 0
      set_result(limited: false, remaining: nil, retry_after_seconds: nil, limit: @limit, window_seconds: @window_seconds)
      return self
    end

    bucket = Time.current.to_i / @window_seconds
    key = "#{@cache_key_prefix}:w:#{bucket}"
    current = (Rails.cache.read(key) || 0).to_i

    if current >= @limit
      retry_after = @window_seconds - (Time.current.to_i % @window_seconds)
      retry_after = 1 if retry_after < 1
      set_result(
        limited: true,
        remaining: 0,
        retry_after_seconds: retry_after,
        limit: @limit,
        window_seconds: @window_seconds
      )
      return self
    end

    ttl = @window_seconds - (Time.current.to_i % @window_seconds) + 1
    Rails.cache.write(key, current + 1, expires_in: ttl.seconds)

    remaining = @limit - current - 1
    set_result(
      limited: false,
      remaining: remaining,
      retry_after_seconds: nil,
      limit: @limit,
      window_seconds: @window_seconds
    )
    self
  end

  # Back-compat helper for merchant-only keys (tests / legacy call sites).
  def self.merchant_window_key(merchant_id, category)
    "api:rl:v1:m:#{merchant_id}:c:#{category}"
  end

  def self.ip_window_key(ip, category)
    safe_ip = ip.to_s.gsub(/[^\h.:a-fA-F]/, '_').presence || 'unknown'
    "api:rl:v1:ip:#{safe_ip}:c:#{category}"
  end
end
