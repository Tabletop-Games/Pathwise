# Backend

> Historical infrastructure. Shipping apps no longer call these endpoints. The code and tests remain for reference and existing deployments.

The Node 22 service targets Cloud Run and Firestore. The HTTP service emits a redacted operation/status/duration record and throttles purchase verification and ad-session creation per installation. Configuration lives in [setup.md](../setup.md). It exposes a purchase readiness probe, Play receipt verification, signed reward callback and receipt endpoints, and Play Games account linking.

- Purchase tokens are sent only to the verifier over HTTPS. Play state, quantity, SKU and obfuscated account must match before a transaction can claim the hashed purchase ID. Client commits the verified grant before consuming or acknowledging. The same installation gets an idempotent response on retry.
- Rewards begin with a short-lived server nonce tied to the installation and ad action. AdMob must sign a callback using a published Google key. Firestore deduplicates by Google transaction ID. A verified receipt must match the requested action.
- Play Games links a Google-verified identity to the installation once. The local ledger remains the gameplay source of truth. Full paid-wallet account recovery, cross-device merge, refund reconciliation and competitive data services require additional implementation.
