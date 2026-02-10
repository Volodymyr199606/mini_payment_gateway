# frozen_string_literal: true

class RateLimiterService < BaseService
  DEFAULT_LIMIT = 100
  DEFAULT_WINDOW = 60 # seconds

  def initialize(merchant:, limit: nil, window: nil)
    super()
    @merchant = merchant
    @limit = limit || DEFAULT_LIMIT
    @window = window || DEFAULT_WINDOW
  end

  def call
    key = rate_limit_key
    current_count = get_current_count(key)

    if current_count >= @limit
      add_error("Rate limit exceeded. Limit: #{@limit} requests per #{@window} seconds")
      set_result({ limited: true, remaining: 0, reset_at: get_reset_time(key) })
      return self
    end

    # Increment counter
    increment_count(key)

    remaining = @limit - (current_count + 1)
    set_result({ limited: false, remaining: remaining, reset_at: get_reset_time(key) })
    self
  end

  private

  def rate_limit_key
    "rate_limit:merchant:#{@merchant.id}"
  end

  def get_current_count(key)
    # Use Rails cache (memory store in dev, Redis in production)
    Rails.cache.read(key) || 0
  end

  def increment_count(key)
    current = get_current_count(key)
    Rails.cache.write(key, current + 1, expires_in: @window.seconds)
  end

  def get_reset_time(_key)
    # Get expiration time from cache
    # Since we can't easily get TTL from Rails cache, estimate based on window
    Time.current + @window.seconds
  end
end
