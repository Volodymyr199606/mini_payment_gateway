# Mini Payment Gateway – Diagrams

Text-based and Mermaid diagrams. For Mermaid, use GitHub, VS Code Mermaid extension, or [mermaid.live](https://mermaid.live).

---

## 1. System Context (C4 Level 1)

```mermaid
C4Context
    title System Context - Mini Payment Gateway

    Person(merchant, "Merchant / Integrator", "Uses API or Dashboard")
    Person(processor, "Processor (Simulated)", "Future: real processor")

    System(gateway, "Mini Payment Gateway", "Rails 7.2 monolith")

    Rel(merchant, gateway, "HTTPS", "REST API / Dashboard")
    Rel(gateway, processor, "Simulated", "No real integration yet")
```

---

## 2. Container Diagram (High-Level)

```mermaid
C4Container
    title Containers - Mini Payment Gateway

    Container_Boundary(rails, "Rails App") {
        Container(api, "REST API", "Rails", "/api/v1")
        Container(dashboard, "Merchant Dashboard", "Rails", "/dashboard")
        Container(services, "Services", "Ruby", "AuthorizeService, etc.")
        Container(models, "Models", "Active Record", "PostgreSQL")
    }

    ContainerDb(db, "PostgreSQL", "Database", "Schema + Data")

    Rel(api, services, "calls")
    Rel(dashboard, services, "calls")
    Rel(services, models, "uses")
    Rel(models, db, "persists")
```

---

## 3. Payment State Machine

```mermaid
stateDiagram-v2
    [*] --> created

    created --> authorized: authorize (success)
    created --> failed: authorize (fail)

    authorized --> captured: capture (success)
    authorized --> failed: capture (fail)
    authorized --> canceled: void (success)

    captured --> captured: refund (partial/full)

    canceled --> [*]
    failed --> [*]
```

---

## 4. Entity Relationship (Simplified)

```mermaid
erDiagram
    Merchant ||--o{ Customer : has
    Customer ||--o{ PaymentMethod : has
    Merchant ||--o{ PaymentIntent : has
    Customer ||--o{ PaymentIntent : pays
    PaymentMethod ||--o{ PaymentIntent : "payment method"
    PaymentIntent ||--o{ Transaction : has
    Transaction ||--o| LedgerEntry : has
    Merchant ||--o{ LedgerEntry : owns
    Merchant ||--o{ IdempotencyRecord : has
    Merchant ||--o{ WebhookEvent : has
    Merchant ||--o{ AuditLog : has
    Merchant ||--o{ ApiRequestStat : has

    Merchant {
        bigint id PK
        string name
        string api_key_digest
        string email
        string password_digest
    }

    PaymentIntent {
        bigint id PK
        bigint merchant_id FK
        bigint customer_id FK
        bigint payment_method_id FK
        int amount_cents
        string status
    }

    Transaction {
        bigint id PK
        bigint payment_intent_id FK
        string kind
        string status
        int amount_cents
    }

    LedgerEntry {
        bigint id PK
        bigint merchant_id FK
        bigint transaction_id FK
        string entry_type
        int amount_cents
    }
```

---

## 5. Request Flow (API Authorize)

```
[Client]  POST /api/v1/payment_intents/1/authorize
    │         X-API-KEY: xxx
    │
    ▼
[Api::V1::PaymentIntentsController#authorize]
    │
    ├─► ApiAuthenticatable: current_merchant
    ├─► IdempotencyService.call
    │       └─► if cached → return 200 + cached body
    │
    ├─► AuthorizeService.call
    │       ├─► Transaction.create!
    │       ├─► PaymentIntent.update!
    │       ├─► ProcessorEventService (WebhookEvent)
    │       └─► AuditLogService
    │
    ├─► IdempotencyService.store_response
    └─► render JSON 200
```

---

## 6. Directory Map (Logical)

```
app/
  controllers/
    api/v1/          ← API surface
    dashboard/       ← Dashboard surface
    concerns/        ← Shared behavior
  models/            ← Domain entities
  services/          ← Business logic (payments, ledger, webhooks)
  jobs/              ← Async (WebhookDeliveryJob)
  middleware/        ← RequestIdMiddleware
```
