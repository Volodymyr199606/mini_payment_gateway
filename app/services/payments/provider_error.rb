# frozen_string_literal: true

module Payments
  class ProviderError < StandardError; end
  class ProviderConfigurationError < ProviderError; end
  class ProviderRequestError < ProviderError; end
  class ProviderSignatureError < ProviderError; end
end
