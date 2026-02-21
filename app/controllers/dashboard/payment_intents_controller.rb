# frozen_string_literal: true

module Dashboard
  class PaymentIntentsController < Dashboard::BaseController
    def index
      @payment_intents = current_merchant.payment_intents
                                         .includes(:customer)
                                         .order(created_at: :desc)
                                         .page(params[:page]).per(25)
    end

    def new
    end

    def create
      amount_cents = params.dig(:payment_intent, :amount_cents).to_s.strip.presence&.to_i
      if amount_cents.blank? || amount_cents <= 0
        @errors = ["Amount must be a positive number"]
        render :new, status: :unprocessable_entity
        return
      end

      customer, payment_method = resolve_or_create_customer_and_payment_method

      @payment_intent = current_merchant.payment_intents.build(
        customer: customer,
        payment_method: payment_method,
        amount_cents: amount_cents,
        currency: "usd",
        status: "created"
      )

      if @payment_intent.save
        redirect_to dashboard_payment_intent_path(@payment_intent), notice: "Payment intent created."
      else
        @errors = @payment_intent.errors.full_messages
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @payment_intent = current_merchant.payment_intents
                                        .includes(:customer, :payment_method, :transactions)
                                        .find(params[:id])

      @transactions = @payment_intent.transactions.order(created_at: :desc)
    end

    # POST /dashboard/payment_intents/:id/authorize
    def authorize
      perform_action(:authorize) do |intent|
        service = AuthorizeService.call(payment_intent: intent, idempotency_key: idempotency_key_for(:authorize, intent.id))
        [service, service.success? ? 'Authorized successfully' : nil]
      end
    end

    # POST /dashboard/payment_intents/:id/capture
    def capture
      perform_action(:capture) do |intent|
        service = CaptureService.call(payment_intent: intent, idempotency_key: idempotency_key_for(:capture, intent.id))
        [service, service.success? ? 'Captured successfully' : nil]
      end
    end

    # POST /dashboard/payment_intents/:id/void
    def void
      perform_action(:void) do |intent|
        service = VoidService.call(payment_intent: intent, idempotency_key: idempotency_key_for(:void, intent.id))
        [service, service.success? ? 'Voided successfully' : nil]
      end
    end

    # POST /dashboard/payment_intents/:id/refund
    def refund
      intent = current_merchant.payment_intents.find(params[:id])

      if intent.status != 'captured'
        redirect_to dashboard_payment_intent_path(intent), alert: 'Capture required first'
        return
      end

      amount_cents = parse_refund_amount(params[:refund], intent)
      if amount_cents == :invalid
        redirect_to dashboard_payment_intent_path(intent), alert: 'Invalid refund amount'
        return
      end

      if amount_cents <= 0 || amount_cents > intent.refundable_cents
        redirect_to dashboard_payment_intent_path(intent), alert: 'Refund amount exceeds refundable amount'
        return
      end

      idempotency_key = idempotency_key_for(:refund, intent.id, amount_cents)

      idempotency = IdempotencyService.call(
        merchant: current_merchant,
        idempotency_key: idempotency_key,
        endpoint: 'refund',
        request_params: { payment_intent_id: intent.id, amount_cents: amount_cents }
      )

      if idempotency.result && idempotency.result[:cached]
        redirect_to dashboard_payment_intent_path(intent), notice: 'Already processed (idempotent)'
        return
      end

      service = RefundService.call(
        payment_intent: intent,
        amount_cents: amount_cents,
        idempotency_key: idempotency_key
      )

      if service.success?
        idempotency.store_response(
          response_body: { refund_amount_cents: amount_cents },
          status_code: 201
        )
        redirect_to dashboard_payment_intent_path(intent), notice: "Refunded #{format_cents(amount_cents)} successfully"
      else
        redirect_to dashboard_payment_intent_path(intent), alert: service.errors.join(', ')
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to dashboard_payment_intents_path, alert: 'Payment intent not found'
    end

    private

    def perform_action(endpoint)
      intent = current_merchant.payment_intents.find(params[:id])
      idempotency_key = idempotency_key_for(endpoint, intent.id)

      idempotency = IdempotencyService.call(
        merchant: current_merchant,
        idempotency_key: idempotency_key,
        endpoint: endpoint.to_s,
        request_params: { payment_intent_id: intent.id }
      )

      if idempotency.result && idempotency.result[:cached]
        redirect_to dashboard_payment_intent_path(intent), notice: 'Already processed (idempotent)'
        return
      end

      service, success_message = yield(intent)

      if service.success?
        idempotency.store_response(
          response_body: { transaction: service.result[:transaction], payment_intent: service.result[:payment_intent] },
          status_code: 200
        )
        redirect_to dashboard_payment_intent_path(intent), notice: success_message
      else
        redirect_to dashboard_payment_intent_path(intent), alert: service.errors.join(', ')
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to dashboard_payment_intents_path, alert: 'Payment intent not found'
    end

    def idempotency_key_for(endpoint, payment_intent_id, extra = nil)
      params[:idempotency_key].presence || SecureRandom.uuid
    end

    def parse_refund_amount(refund_params, intent)
      return intent.refundable_cents if refund_params.blank? || refund_params[:amount_cents].blank?
      raw = refund_params[:amount_cents].to_s.strip
      return intent.refundable_cents if raw.empty?
      return :invalid unless raw.match?(/\A\d+\z/)
      raw.to_i
    end

    def format_cents(cents)
      return 'remaining' if cents.nil?
      "%.2f" % (cents / 100.0)
    end

    # Returns [customer, payment_method] for use when creating a payment intent.
    # Uses most recent existing records, or creates default ones if none exist.
    def resolve_or_create_customer_and_payment_method
      customer = current_merchant.customers.order(created_at: :desc).first
      if customer.nil?
        slug = default_customer_email_slug
        email = slug.present? ? "customer@#{slug}.example" : "customer@example.com"
        customer = current_merchant.customers.create!(
          name: "Default Customer",
          email: email
        )
      end

      payment_method = customer.payment_methods.order(created_at: :desc).first
      if payment_method.nil?
        payment_method = customer.payment_methods.create!(
          method_type: "card",
          brand: "Visa",
          last4: "4242",
          exp_month: 12,
          exp_year: Date.current.year + 2,
          token: "pm_demo_#{SecureRandom.hex(8)}"
        )
      end

      [customer, payment_method]
    end

    def default_customer_email_slug
      name = current_merchant.name.to_s.strip
      return "" if name.blank?
      name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    end
  end
end
