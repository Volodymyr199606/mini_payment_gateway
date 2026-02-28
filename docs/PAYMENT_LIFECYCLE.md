# Payment Lifecycle: Authorize vs Capture

This document explains how payment intents move through statuses and how **authorize**, **capture**, **void**, and **refund** work in this gateway. It uses a simulated processor; no real card charges occur. Ledger entries are created only on **capture** (charge) and **refund** (refund), not on authorize or void.

---

## Overview

A payment intent represents a single payment flow. The merchant creates an intent, then either **authorizes** (hold funds) and later **captures** (settle) or **voids** (release hold), or authorizes and captures in one flow. After capture, **refunds** can be issued. All processor calls are simulated; the gateway enforces a strict state machine and creates ledger entries only when money is considered settled (capture) or returned (refund).

---

## Payment Intent statuses

The gateway uses exactly these statuses (from the `PaymentIntent` model):

| Status      | Meaning |
|------------|---------|
| `created`  | Intent created; no authorize/capture/void/refund has succeeded yet. |
| `authorized` | Authorize succeeded; funds are held. Intent is eligible for capture or void. |
| `captured` | Capture succeeded; funds are settled. Intent is eligible for refund(s). |
| `canceled` | Void succeeded; the authorization was released. Intent is terminal. |
| `failed`   | Authorize (or capture in some flows) failed, or processor timeout on authorize. Intent is terminal. |

Valid transitions:

- `created` → `authorized` (authorize success) or `failed` (authorize failure/timeout)
- `authorized` → `captured` (capture success), `failed` (capture failure), or `canceled` (void success)
- `captured` → remains `captured` (refunds do not change intent status)
- `created` or `authorized` → `canceled` (void success)

---

## Authorize vs Capture

### Authorize (in this project)

- **What it does:** Simulated processor authorize—request to hold the payment amount. The processor approves or declines; no money moves to the merchant.
- **When it runs:** Only when the payment intent is in status `created`.
- **Status transition on success:** Payment intent status is set to **`authorized`**. A **Transaction** is created with `kind: 'authorize'`, `status: 'succeeded'`.
- **Timeout behavior (see [TIMEOUTS.md](TIMEOUTS.md)):** Authorize timeout → payment intent is set to **`failed`**. A transaction with `kind: 'authorize'`, `status: 'failed'`, `failure_code: 'timeout'` is created. Intent is terminal.
- **Ledger behavior:** No ledger entries are created on authorize. Funds are held, not settled.
- **Idempotency:** Authorize uses idempotency protection. Same idempotency key returns the same response; only one authorize transaction is created.
- **On failure (non-timeout):** A transaction with `kind: 'authorize'`, `status: 'failed'` is created, and the payment intent status is set to **`failed`**.

### Capture (in this project)

- **What it does:** Request to settle the previously authorized amount. Simulated processor capture; money is considered to move to the merchant.
- **When it runs:** Only when the payment intent is in status `authorized` (and not already captured).
- **Status transition on success:** Payment intent status is set to **`captured`**. A **Transaction** is created with `kind: 'capture'`, `status: 'succeeded'`.
- **Ledger entries created:** One **LedgerEntry** with `entry_type: 'charge'`, positive `amount_cents`. This is the only place a charge (money in) is written to the ledger. Fee entries if applicable.
- **Timeout behavior (see [TIMEOUTS.md](TIMEOUTS.md)):** Capture timeout → payment intent status **remains `authorized`** (unchanged). A transaction with `kind: 'capture'`, `status: 'failed'`, `failure_code: 'timeout'` is created. No ledger entry is created.
- **Idempotency:** Capture uses idempotency protection. Same idempotency key returns the same response; only one capture transaction and one charge ledger entry.
- **On failure (non-timeout):** A transaction with `kind: 'capture'`, `status: 'failed'` is created; the payment intent status **remains `authorized`**. No ledger entry is created.

### Void (related action)

- **What it means:** Release the authorization so the held funds are never captured.
- **When it runs:** When the payment intent is in status `created` or `authorized`.
- **On success:** Payment intent status is set to **`canceled`**. No ledger entry is created (authorize never created a charge; void only releases the hold).

### Refund (related action)

- **What it means:** Return some or all of the captured amount to the customer.
- **When it runs:** Only when the payment intent is in status **`captured`**.
- **On success:** A **LedgerEntry** is created: `entry_type: 'refund'`, **negative** `amount_cents`. The payment intent status **remains `captured`** (unchanged). Partial or full refunds are supported up to the refundable amount.

---

## Timeouts behavior

Behavior matches [TIMEOUTS.md](TIMEOUTS.md):

- **Authorize timeout:** The simulated processor call is aborted. The payment intent is set to **`failed`**. A transaction with `kind: 'authorize'`, `status: 'failed'`, `failure_code: 'timeout'` is created.
- **Capture / void / refund timeout:** The payment intent status is **unchanged**. A failed transaction is created for the attempted operation with `failure_code: 'timeout'`. No partial state (e.g. no ledger entry is created on a capture that times out).

---

## Ledger implications

Aligned with [DATA_FLOW.md](DATA_FLOW.md) and the current implementation:

- **Ledger entries are created only on capture and refund.**
  - **Capture (success):** One ledger entry, `entry_type: 'charge'`, positive `amount_cents` (money in).
  - **Refund (success):** One ledger entry per refund, `entry_type: 'refund'`, negative `amount_cents` (money out).
- **Authorize** and **void** do **not** create ledger entries. Authorize holds funds; void releases the hold. Neither is a settlement event.

---

## Example timelines

### Create → Authorize → Capture

1. **Create:** Payment intent is created with status `created`.
2. **Authorize:** Client calls authorize. Simulated processor approves. Status → `authorized`. No ledger entry.
3. **Capture:** Client calls capture. Simulated processor approves. Status → `captured`. One **charge** ledger entry (positive amount). The merchant’s ledger now shows the settled amount.

### Capture → Refund

1. Payment intent is already `captured` (one successful capture and one charge ledger entry).
2. **Refund:** Client calls refund (full or partial). Simulated processor approves. One **refund** ledger entry (negative amount). Status remains `captured`. Refunds can be repeated until the refundable amount is exhausted.

These examples are conceptual; no PAN, secrets, or raw card data are involved in the lifecycle docs.
