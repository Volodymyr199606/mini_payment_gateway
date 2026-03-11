# frozen_string_literal: true

# Route constraint: only allow dev/test environments.
# Use for /dev/* routes to block production.
class DevRoutesConstraint
  def self.matches?(_request)
    Rails.env.development? || Rails.env.test?
  end
end
