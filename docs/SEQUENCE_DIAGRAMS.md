# Mini Payment Gateway – Sequence Diagrams

Mermaid diagrams for key flows. Use a Mermaid-capable viewer (e.g. GitHub, VS Code extension) to render.

---

## 1. Authorize Flow (API)

```mermaid
sequenceDiagram
    participant Client
    participant API as Api::V1::PaymentIntentsController
    participant Idempotency as IdempotencyService
    participant Auth as AuthorizeService
    participant DB as PostgreSQL

    Client->>API: POST /payment_intents/:id/authorize
    API->>API: Load payment_intent (current_merchant)
    API->>Idempotency: call(merchant, idempotency_key, endpoint: 'authorize', request_params)
    alt Cached response exists
        Idempotency-->>API: cached: true, response_body
        API-->>Client: 200 + cached JSON
    else No cache
        Idempotency-->>API: cached: false
        API->>Auth: call(payment_intent:, idempotency_key:)
        Auth->>DB: Transaction.create!(kind: 'authorize', status: succeeded/failed)
        Auth->>DB: payment_intent.update!(status: authorized/failed)
        Auth->>DB: AuditLog, WebhookEvent (via ProcessorEventService)
        Auth-->>API: service.success? + result
        API->>Idempotency: store_response(response_body, status_code)
        API-->>Client: 200 + JSON or error
    end
```

---

## 2. Capture Flow (with Ledger)

```mermaid
sequenceDiagram
    participant Client
    participant API as Api::V1::PaymentIntentsController
    participant Idempotency as IdempotencyService
    participant Capture as CaptureService
    participant Ledger as LedgerService
    participant DB as PostgreSQL

    Client->>API: POST /payment_intents/:id/capture
    API->>Idempotency: call(merchant, idempotency_key, endpoint: 'capture')
    alt Cached
        Idempotency-->>API: cached response
        API-->>Client: 200 + cached
    else New
        API->>Capture: call(payment_intent:, idempotency_key:)
        Capture->>DB: Transaction.create!(kind: 'capture', status: succeeded/failed)
        Capture->>DB: payment_intent.update!(status: captured/failed)
        alt Success
            Capture->>Ledger: call(entry_type: 'charge', amount_cents: +)
            Ledger->>DB: LedgerEntry.create!
        end
        Capture->>DB: WebhookEvent (ProcessorEventService)
        Capture-->>API: result
        API->>Idempotency: store_response(...)
        API-->>Client: 200 + JSON
    end
```

---

## 3. Refund Flow (Partial/Full)

```mermaid
sequenceDiagram
    participant Client
    participant API as Api::V1::RefundsController
    participant Idempotency as IdempotencyService
    participant Refund as RefundService
    participant Ledger as LedgerService
    participant DB as PostgreSQL

    Client->>API: POST /payment_intents/:id/refunds
    API->>API: Validate status == captured, amount <= refundable_cents
    API->>Idempotency: call(merchant, idempotency_key, endpoint: 'refund', request_params: {amount_cents})
    alt Cached
        Idempotency-->>API: cached
        API-->>Client: 201 + cached
    else New
        API->>Refund: call(payment_intent:, amount_cents:, idempotency_key:)
        Refund->>DB: Transaction.create!(kind: 'refund', status: succeeded/failed)
        alt Success
            Refund->>Ledger: call(entry_type: 'refund', amount_cents: -refund_amount)
            Ledger->>DB: LedgerEntry.create!
        end
        Refund->>DB: WebhookEvent
        Refund-->>API: result
        API->>Idempotency: store_response(...)
        API-->>Client: 201 + JSON
    end
```

---

## 4. Webhook Delivery (Async)

```mermaid
sequenceDiagram
    participant Service as AuthorizeService / CaptureService / RefundService
    participant Processor as ProcessorEventService
    participant DB as PostgreSQL
    participant Job as WebhookDeliveryJob
    participant HTTP as WebhookDeliveryService
    participant Merchant as Merchant Webhook URL

    Service->>Processor: call(event_type:, payload:)
    Processor->>DB: WebhookEvent.create!(event_type, payload, delivery_status: 'pending')
    Processor->>DB: WebhookSignatureService.generate_signature(payload)
    Processor->>DB: webhook_event.update!(signature:)
    Note over DB: WebhookEvent after_commit
    DB->>Job: perform_later(webhook_event.id)
    Job->>HTTP: call(webhook_event:, merchant_webhook_url:)
    HTTP->>Merchant: POST JSON, X-WEBHOOK-SIGNATURE
    alt 2xx
        HTTP->>DB: delivery_status: 'succeeded', delivered_at
    else Non-2xx or error
        HTTP->>Job: perform_later (retry with backoff)
    end
```

---

## 5. Dashboard Create Payment Intent (Simplified)

```mermaid
sequenceDiagram
    participant User
    participant Dashboard as Dashboard::PaymentIntentsController
    participant DB as PostgreSQL

    User->>Dashboard: POST /dashboard/payment_intents (amount_cents only)
    Dashboard->>Dashboard: resolve_or_create_customer_and_payment_method
    alt No customers
        Dashboard->>DB: Customer.create!(name: 'Default Customer', email: customer@slug.example)
    else Has customers
        Dashboard->>DB: customers.order(created_at: :desc).first
    end
    alt No payment methods for customer
        Dashboard->>DB: PaymentMethod.create!(brand: 'Visa', last4: '4242', ...)
    end
    Dashboard->>DB: PaymentIntent.create!(customer:, payment_method:, amount_cents:, currency: 'usd')
    Dashboard-->>User: redirect to /dashboard/payment_intents/:id
```

---

## 6. Idempotency Lookup

```mermaid
sequenceDiagram
    participant Controller
    participant Idempotency as IdempotencyService
    participant DB as IdempotencyRecord

    Controller->>Idempotency: call(merchant:, idempotency_key:, endpoint:, request_params:)
    Idempotency->>DB: find_by(merchant, idempotency_key, endpoint)
    alt Record exists
        DB-->>Idempotency: existing_record
        Idempotency-->>Controller: { cached: true, response_body, status_code }
    else No record
        Idempotency->>DB: IdempotencyRecord.create!(..., response_body: {pending: true})
        Idempotency-->>Controller: { cached: false, idempotency_record }
    end
```
