# frozen_string_literal: true

module Dashboard
  class WebhooksController < Dashboard::BaseController
    def index
      @webhook_events = current_merchant.webhook_events
                                        .order(created_at: :desc)
                                        .page(params[:page]).per(25)
    end
  end
end
