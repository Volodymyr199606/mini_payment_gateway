# Mini Payment Gateway – Deployment

---

## 1. Tech Stack (Runtime)

| Component | Version / Choice |
|-----------|------------------|
| Ruby | >= 3.1.0 |
| Rails | 7.2 |
| Database | PostgreSQL |
| Web Server | Puma (default) |

---

## 2. Environment Variables

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | PostgreSQL connection string |
| `WEBHOOK_SECRET` | HMAC secret for webhook signatures |
| `MERCHANT_WEBHOOK_URL` | (Optional) Default webhook URL for outbound delivery |
| `PROCESSOR_TIMEOUT_SECONDS` | (Optional) Timeout for simulated processor calls; default 3 |
| `WEBHOOK_OPEN_TIMEOUT_SECONDS` | (Optional) HTTP open timeout for webhook delivery |
| `WEBHOOK_READ_TIMEOUT_SECONDS` | (Optional) HTTP read timeout for webhook delivery |

---

## 3. Background Jobs

- **WebhookDeliveryJob:** Delivers webhooks asynchronously. Requires Active Job backend (e.g. Solid Queue, Sidekiq).
- **Assumption:** Default adapter may be `:async` in development; production should use a persistent backend.

---

## 4. Deployment Artifacts (Existing)

The repo includes:

- `config/deploy.yml` – Kamal deployment config
- `Dockerfile` – Container build
- `docker-compose.yml` – Local Docker setup

**Assumption:** Kamal targets a VPS or similar. No Kubernetes/ECS-specific docs.

---

## 5. Database

- Migrations: `rails db:migrate`
- Seeds: `rails db:seed` (creates test merchants, customers, payment intents, transactions)

---

## 6. Production Checklist

1. Set `RAILS_ENV=production`
2. Set `SECRET_KEY_BASE`
3. Configure `DATABASE_URL`
4. Set `WEBHOOK_SECRET`
5. Configure Active Job backend for `WebhookDeliveryJob`
6. Ensure PostgreSQL is available and migrated
7. Run `rails assets:precompile` if serving assets
