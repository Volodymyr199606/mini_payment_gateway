# frozen_string_literal: true

# Load perf harness (used by `rake perf:*` and specs). Keeps load order stable.
module MiniPaymentGatewayPerf
end

require_relative 'mini_payment_gateway_perf/metrics'
require_relative 'mini_payment_gateway_perf/report'
require_relative 'mini_payment_gateway_perf/stubs'
require_relative 'mini_payment_gateway_perf/world'
require_relative 'mini_payment_gateway_perf/harness'
require_relative 'mini_payment_gateway_perf/runner'
require_relative 'mini_payment_gateway_perf/scenarios'
