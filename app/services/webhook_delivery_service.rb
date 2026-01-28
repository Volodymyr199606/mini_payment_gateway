require "net/http"
require "uri"

class WebhookDeliveryService < BaseService
  MAX_ATTEMPTS = 3
  BACKOFF_MULTIPLIER = 2

  def initialize(webhook_event:, merchant_webhook_url: nil)
    super()
    @webhook_event = webhook_event
    @merchant_webhook_url = merchant_webhook_url || merchant_webhook_url_from_config
  end

  def call
    if @merchant_webhook_url.blank?
      # No webhook URL configured - mark as succeeded (stored for viewing)
      @webhook_event.update!(
        delivery_status: "succeeded",
        delivered_at: Time.current
      )
      set_result({ delivered: false, reason: "no_url_configured" })
      return self
    end

    @webhook_event.increment!(:attempts)

    begin
      response = deliver_webhook

      if response.is_a?(Net::HTTPSuccess)
        @webhook_event.update!(
          delivery_status: "succeeded",
          delivered_at: Time.current
        )
        set_result({ delivered: true, status_code: response.code })
      else
        handle_delivery_failure(response)
      end
    rescue StandardError => e
      handle_delivery_error(e)
    end

    self
  end

  private

  def deliver_webhook
    uri = URI.parse(@merchant_webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.read_timeout = 10
    http.open_timeout = 5

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request["X-WEBHOOK-SIGNATURE"] = @webhook_event.signature if @webhook_event.signature
    request["X-WEBHOOK-EVENT-TYPE"] = @webhook_event.event_type
    request.body = @webhook_event.payload.to_json

    http.request(request)
  end

  def handle_delivery_failure(response)
    if @webhook_event.attempts >= MAX_ATTEMPTS
      @webhook_event.update!(delivery_status: "failed")
      add_error("Webhook delivery failed after #{MAX_ATTEMPTS} attempts")
    else
      # Schedule retry with exponential backoff
      delay = calculate_backoff(@webhook_event.attempts)
      WebhookDeliveryJob.set(wait: delay.seconds).perform_later(@webhook_event.id)
      add_error("Webhook delivery failed (attempt #{@webhook_event.attempts}/#{MAX_ATTEMPTS})")
    end
  end

  def handle_delivery_error(exception)
    Rails.logger.error("Webhook delivery error: #{exception.message}")
    
    if @webhook_event.attempts >= MAX_ATTEMPTS
      @webhook_event.update!(delivery_status: "failed")
      add_error("Webhook delivery error: #{exception.message}")
    else
      delay = calculate_backoff(@webhook_event.attempts)
      WebhookDeliveryJob.set(wait: delay.seconds).perform_later(@webhook_event.id)
      add_error("Webhook delivery error (attempt #{@webhook_event.attempts}/#{MAX_ATTEMPTS})")
    end
  end

  def calculate_backoff(attempt_number)
    BACKOFF_MULTIPLIER ** attempt_number
  end

  def merchant_webhook_url_from_config
    # In production, this would come from merchant settings
    # For now, use environment variable or return nil
    ENV["MERCHANT_WEBHOOK_URL"]
  end
end
