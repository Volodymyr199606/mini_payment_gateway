class WebhookSignatureService < BaseService
  def initialize(payload:, signature:)
    super()
    @payload = payload
    @signature = signature
  end

  def call
    secret = webhook_secret
    
    if secret.blank?
      add_error("Webhook secret not configured")
      return self
    end

    expected_signature = generate_signature(@payload, secret)
    
    # Use secure comparison to prevent timing attacks
    if ActiveSupport::SecurityUtils.secure_compare(expected_signature, @signature)
      set_result(true)
    else
      add_error("Invalid webhook signature")
      set_result(false)
    end

    self
  end

  def self.generate_signature(payload, secret)
    OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
  end

  private

  def generate_signature(payload, secret)
    self.class.generate_signature(payload, secret)
  end

  def webhook_secret
    Rails.application.config.webhook_secret
  end
end
