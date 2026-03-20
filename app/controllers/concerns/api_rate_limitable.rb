# frozen_string_literal: true

# Central API v1 throttling: prepended IP/public limits, then merchant-scoped limits after auth.
module ApiRateLimitable
  extend ActiveSupport::Concern

  included do
    prepend_before_action :enforce_prepended_api_rate_limits
    before_action :enforce_authenticated_api_rate_limits
  end

  private

  # Webhook ingress and disabled public merchant signup — no API key; scope by IP.
  def enforce_prepended_api_rate_limits
    if controller_path == 'api/v1/webhooks' && action_name == 'processor'
      return apply_ip_rate_limit('webhook_ingress')
    end

    if controller_path == 'api/v1/merchants' && action_name == 'create'
      return apply_ip_rate_limit('public_registration')
    end

    nil
  end

  def enforce_authenticated_api_rate_limits
    return unless current_merchant

    category = ApiRateLimits::Catalog.resolve(controller_path: controller_path, action_name: action_name)
    cfg = ApiRateLimits.for_category(category)
    prefix = RateLimiterService.merchant_window_key(current_merchant.id, category)
    apply_rate_limit_service(prefix, cfg, scope: 'merchant', category: category)
  end

  def apply_ip_rate_limit(category)
    cfg = ApiRateLimits.for_category(category)
    prefix = RateLimiterService.ip_window_key(request.remote_ip, category)
    apply_rate_limit_service(prefix, cfg, scope: 'ip', category: category)
  end

  def apply_rate_limit_service(prefix, cfg, scope:, category:)
    svc = RateLimiterService.call(
      cache_key_prefix: prefix,
      limit: cfg[:limit],
      window_seconds: cfg[:window_seconds]
    )

    if svc.result[:limited]
      log_api_rate_limited(scope: scope, category: category, limit: svc.result[:limit], window_seconds: svc.result[:window_seconds])
      response.set_header('Retry-After', svc.result[:retry_after_seconds].to_s) if svc.result[:retry_after_seconds]
      response.set_header('X-RateLimit-Limit', svc.result[:limit].to_s) if svc.result[:limit]
      response.set_header('X-RateLimit-Remaining', '0')
      render_error(
        code: 'rate_limited',
        message: 'Too many requests. Please slow down and try again later.',
        status: :too_many_requests,
        details: {
          retry_after_seconds: svc.result[:retry_after_seconds]
        }
      )
      # AbstractController skips after_action when a before_action halts; record 429 metrics explicitly.
      record_api_rate_limit_stat_if_merchant!
      return false
    end

    response.set_header('X-RateLimit-Limit', svc.result[:limit].to_s) if svc.result[:limit]
    response.set_header('X-RateLimit-Remaining', svc.result[:remaining].to_s) if svc.result.key?(:remaining)
    nil
  end

  def record_api_rate_limit_stat_if_merchant!
    return unless current_merchant

    ApiRequestStat.record_request!(
      merchant_id: current_merchant.id,
      is_error: false,
      is_rate_limited: true
    )
  end

  def log_api_rate_limited(scope:, category:, limit:, window_seconds:)
    payload = {
      timestamp: Time.current.iso8601,
      service: 'mini_payment_gateway',
      event: 'api_rate_limited',
      limit_exceeded: true,
      scope: scope,
      limiter_category: category,
      limit: limit,
      window_seconds: window_seconds,
      merchant_id: current_merchant&.id,
      path: request.path,
      request_id: request.request_id || Thread.current[:request_id]
    }
    payload[:ip_hashed] = Digest::SHA256.hexdigest(request.remote_ip.to_s)[0, 16] if scope == 'ip'
    Rails.logger.warn(payload.to_json)
  end
end
