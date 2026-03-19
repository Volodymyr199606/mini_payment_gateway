# frozen_string_literal: true

require 'stringio'

module MiniPaymentGatewayPerf
  # Rack integration session for black-box timing of real controller stack.
  class Harness
    attr_reader :session

    def initialize
      @session = ActionDispatch::Integration::Session.new(Rails.application)
    end

    def get(path, **opts)
      @session.get(path, **opts)
      @session.response.status
    end

    def post(path, **opts)
      @session.post(path, **opts)
      @session.response.status
    end

    def response_json
      JSON.parse(@session.response.body)
    rescue JSON::ParserError
      {}
    end

    def csrf_token_from(html)
      return if html.blank?

      html[/name="authenticity_token"\s+value="([^"]+)"/, 1] ||
        html[/name="csrf-token"\s+content="([^"]+)"/, 1] ||
        html[/content="([^"]+)"\s+name="csrf-token"/, 1]
    end

    # Sign in via email/password; follows redirects.
    # If already authenticated, GET /dashboard/sign_in redirects away — skip posting credentials.
    def dashboard_sign_in!(email:, password:)
      @session.get('/dashboard/sign_in')
      follow_redirects!
      path = @session.request&.path.to_s
      return if @session.response.successful? && !path.include?('sign_in')

      tok = csrf_token_from(@session.response.body)
      raise 'CSRF token missing' if tok.blank?

      @session.post(
        '/dashboard/sign_in',
        params: { email: email, password: password, authenticity_token: tok }
      )
      follow_redirects!
      raise "Dashboard sign-in failed (status #{@session.response.status})" unless @session.response.successful?
    end

    def follow_redirects!
      hops = 0
      while @session.response.redirect? && hops < 10
        @session.follow_redirect!
        hops += 1
      end
    end

    def dashboard_post_json(path, params:, csrf_token:)
      # Match request-spec pattern: Hash + as: :json + X-CSRF-Token (not raw JSON string).
      @session.post(
        path,
        params: params,
        headers: {
          'Accept' => 'application/json',
          'X-CSRF-Token' => csrf_token
        },
        as: :json
      )
    end

    # Merchant API (X-API-KEY); +params+ is a Ruby Hash serialized as JSON body.
    def api_post(path, world, params)
      @session.post(path, params: params.to_json, headers: world.api_headers)
      @session.response.status
    end

    def api_get(path, world)
      @session.get(path, headers: world.api_headers)
      @session.response.status
    end

    # Full Rack call so request.body matches signed bytes (Integration POST can mangle JSON body).
    def post_webhook_raw(body_json, signature)
      env = Rack::MockRequest.env_for(
        '/api/v1/webhooks/processor',
        method: 'POST',
        input: StringIO.new(body_json),
        'CONTENT_TYPE' => 'application/json',
        'CONTENT_LENGTH' => body_json.bytesize.to_s,
        'HTTP_X_WEBHOOK_SIGNATURE' => signature
      )
      status, = Rails.application.call(env)
      status
    end

    # Dashboard AI chat: session auth + CSRF from GET /dashboard/sign_in with redirect follow
    # (same pattern as spec/requests/dashboard_ai_spec.rb #csrf_token).
    def dashboard_ai_chat!(world, message:, agent: nil)
      dashboard_sign_in!(email: world.email, password: world.password)
      @session.get('/dashboard/sign_in')
      follow_redirects!
      tok = csrf_token_from(@session.response.body)
      raise 'CSRF missing for dashboard AI' if tok.blank?

      body = { message: message }
      body[:agent] = agent if agent.present?
      dashboard_post_json('/dashboard/ai/chat', params: body, csrf_token: tok)
      @session.response.status
    end

    def dashboard_get(path)
      @session.get(path)
      @session.response.status
    end
  end
end
