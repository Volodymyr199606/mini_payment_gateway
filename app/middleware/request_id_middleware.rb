class RequestIdMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request_id = env["HTTP_X_REQUEST_ID"] || generate_request_id
    env["request_id"] = request_id
    
    # Set in thread-local storage for logging
    Thread.current[:request_id] = request_id
    
    status, headers, response = @app.call(env)
    
    # Add request ID to response headers
    headers["X-Request-ID"] = request_id
    
    [status, headers, response]
  ensure
    # Clean up thread-local storage
    Thread.current[:request_id] = nil
  end

  private

  def generate_request_id
    SecureRandom.uuid
  end
end
