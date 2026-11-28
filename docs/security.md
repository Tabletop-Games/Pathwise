# Security

Pathwise has no server. Everything runs on the device, with Google Play Games Services (saved games), Google Play Billing and AdMob as the only remote parties. Read this with [cloud saves](cloud-saves.md), which describes the sync rules and connectivity handling.

## What is protected

- **Secrets never ship in the app.** The repository holds no service-account keys, signing material, OAuth client secrets or receipt tokens. The Play Games project number and the Play licensing public key are public configuration and are read at build time. CI scans tracked files for private-key and token patterns.
- **Play Billing verification** happens on the device: the purchase signature is checked against the licensing public key, the package name, product and token must match the purchase record, and pending or cancelled purchases are never granted.
- **Purchase grants are durable and deduplicated.** A grant is keyed by a hash of the purchase token and is recorded before a consumable is consumed. Premium's bonus has a fixed ledger ID.
- **Permanent entitlements follow Google Play.** On each start the app queries the owned permanent products and sets the entitlements to match, so a refund removes them.
- **Saved games are private to the player.** Saved Games are scoped to the player's own Google account and the Pathwise game project.
- **Credentials stay out of backups.** Android backup is disabled (`allowBackup="false"`). The device save is a cache, and Saved Games is the recovery mechanism, so a backup cannot resurrect a stale copy.
- **Debug and production are isolated.** Debug builds use `.debug` preference keys and a local fake save unless Play Games is explicitly enabled for the debug package. No debug grant or test purchase can reach a production save.
- **Cloud saves are validated on read.** A save must parse, carry the expected format and version, and match its payload and economy digests. Anything else is treated as damaged and is not written over.
- **Rewards and purchases are limited on the device.** Daily ad limits, one reward per ad instance, and one grant per purchase token stop accidental over-claiming and repeated grants.

## Accepted limitations

These are intentional trade-offs of avoiding a hosted backend. They are not bugs to fix in the client.

1. **A modified app can change local state**: coins, hints, route, and the save itself. Checksums and digests detect corruption and careless editing. They do not stop someone who recomputes a valid digest. Coins are not tamper-proof, and Pathwise does not claim otherwise.
2. **The cloud save is not an authoritative ledger.** Two offline devices can each spend the same coins. The conflict prompt makes the player choose one copy when both changed economy, so no coins are created silently, but a determined player can still exploit the window.
3. **Client-side advertisement rewards are verified on the device.** A modified app can claim a reward. Google's rewarded-ad callbacks reach only the device, so there is no server-side check.
4. **Consumed coin packs can be lost** if every copy of the save is lost before the cloud accepts the write. Google Play does not keep consumed purchases, so they cannot be rebuilt from Billing.
5. **Refund reconciliation is limited.** Coin packs cannot be reconciled after consumption. Permanent products are reconciled against Google Play's owned list at each start.
6. **Device time is not trusted.** Daily limits and cooldowns use the device clock, so changing it can reset a day. Time Attack deadlines use the elapsed-time clock, which does not reset when the wall clock changes.
7. **Play Integrity is not used.** It requires a backend to decrypt verdicts, and this architecture has none. Adding Google's client-side attestation without server verification would not be meaningful, so it is not included.
8. **Internet checks are not a security boundary.** The connectivity probe only decides whether network features are offered. A modified app can ignore it.

Pathwise does not detect or circumvent VPNs, DNS filters or privacy tools.

## Reporting

Report suspected vulnerabilities privately to the maintainers rather than in a public issue.
