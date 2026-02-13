# frozen_string_literal: true

module Dashboard
  class OverviewController < Dashboard::BaseController
    def index
      @metrics = MetricsService.compute(merchant: current_merchant)
    end
  end
end
