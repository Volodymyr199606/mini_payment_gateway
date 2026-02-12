# PCI DSS Compliance Awareness

This document provides PCI compliance awareness for the mini payment gateway. It is **documentation only**—no encryption, card storage, or PCI-specific logic is implemented.

---

## 1. What is PCI DSS?

**PCI DSS** (Payment Card Industry Data Security Standard) is a set of security standards for organizations that handle cardholder data. It exists to reduce fraud and protect cardholder information (Primary Account Number, CVV, expiry, etc.) throughout the payment lifecycle.

---

## 2. PCI Scope Analysis of This Project

| Aspect | Status |
|--------|--------|
| **Raw card data (PAN, CVV)** | **Not stored or processed.** |
| **Cardholder data in transit** | Application never receives full card numbers. |
| **Tokenization** | Uses `PaymentMethod.token`—clients reference payment methods by token, not raw card data. |

**Key point:** The backend never receives, logs, or persists full Primary Account Numbers (PAN) or CVV. Payment methods are created with only safe, truncated metadata (`last4`, `exp_month`, `exp_year`, `brand`) plus an opaque token.

---

## 3. Tokenization and PCI Scope Reduction

**Tokenization** means replacing sensitive card data with a non-sensitive reference (token). If the token is compromised, it cannot be used to reconstruct the original card number.

- **Token:** `PaymentMethod.token` (e.g. `pm_abc123...`) — generated and stored by this application.
- **Effect:** The backend operates only on tokens. Raw card data is expected to be collected, tokenized, and handled by a PCI-compliant processor or hosted checkout, not by this application.

Using tokens reduces PCI scope because the application does not store, process, or transmit cardholder data.

---

## 4. Responsibility Split

| Component | Responsibility |
|-----------|----------------|
| **Client / Checkout** | Collect card data in a PCI-compliant manner (e.g. hosted fields, iframe, redirect). Never send PAN or CVV to the application backend. Obtain tokens from a compliant processor. |
| **Payment processor** | Accept raw card data, tokenize it, process payments. Must be PCI DSS compliant. |
| **Backend application** | Accept and store only tokens and non-sensitive metadata. Never touch raw card data. |
| **Database** | Store tokens and metadata only. No PAN or CVV. |
| **Infrastructure** | Secure network, access control, logging (ensure tokens and other sensitive identifiers are not logged). |

---

## 5. What Is Intentionally NOT Implemented

- Card data encryption at rest
- CVV storage or handling
- Full PAN storage or transmission
- PCI DSS-specific controls (key management, network segmentation, vulnerability scanning)
- SAQ or ROC processes
- Tokenization via a certified processor (this project uses internal tokens for simulation only)
- Card validation logic beyond basic expiry/metadata checks

---

## 6. Production Deployment Considerations

In a real production deployment, you would typically need:

- **PCI-compliant tokenization** via a certified processor (Stripe, Adyen, etc.), not internal token generation.
- **Encryption in transit** (TLS) and at rest for stored data.
- **Access controls** and audit logging for systems that handle payment data.
- **Vulnerability management** and secure development practices.
- **SAQ** (Self-Assessment Questionnaire) or **ROC** (Report on Compliance) as required by your acquiring bank.
- **Hosted checkout / iframe** so card data never touches your servers.

This project is for learning and simulation; production use would require full PCI DSS assessment and appropriate controls.
