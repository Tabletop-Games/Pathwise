# Cloud saves

Pathwise has no server of its own. The device keeps the save, and Google Play Games Services Saved Games keeps a copy in the player's Google account. This copy is what lets a player restore progress on a new phone or after reinstalling.

This document describes the design, the rules a sync pass follows, and what the design can and cannot guarantee. The developer-facing setup steps are in [Play Console setup](play-console-setup.md).

## What is stored

One saved game per player, named `pathwise-progress-v1` (debug builds use a local test store, see below). Its payload is the same snapshot map the app writes to the device, so there is one schema and one migration path.

The cloud envelope uses canonical JSON with optional gzip compression:

| Field | Meaning |
| --- | --- |
| `format`, `version` | `pathwise-cloud`, version 4. Versions 1–3 remain readable. Version 1 is verified and migrated to Classic tip defaults. Versions 1 and 2 start discovery progress prospectively unless the payload already includes it. |
| `revision` | Increments on every successful upload. Used to detect remote changes. |
| `savedAt` | Upload time in milliseconds, for display only. |
| `economy` | SHA-256 of the economy unit (below). Lets a device compare copies without parsing both. |
| `payloadDigest` | SHA-256 of the whole payload. Detects corruption or tampering. |
| `payload` | Coins, hints, purchases and entitlement flags, research, boosts, chapter chests, discoveries, streak, achievements, results, daily and Time Attack records, tutorials, preferences, and the unfinished route. |

Canonical JSON (sorted keys) keeps digests stable across devices. Envelopes of at least 64 KiB are gzip-compressed. The transport limit remains 2 MiB, and the decoder allows at most 64 MiB after expansion. The bound protects mobile memory. A save beyond either limit cannot sync to the single Play Games slot but remains local.

Excluded: Play Games and Play Billing tokens, account identifiers (only a hash of the player ID is kept, and only to detect an account switch), device identifiers, and any secrets. Purchase tokens are not stored. The grant record is a hash of the token, so a purchase cannot be credited twice.

### Economy and progress

The payload splits in two:

- **Economy**: everything except the keys listed as progress. A change here means coins, hints, purchases, results or rewards changed.
- **Progress**: tutorial acknowledgements, the unfinished route (`attempts`), play time, preferences, the activity counters and the last ad time. These merge safely.

Crate timers are excluded from the economy digest because they change every few seconds during play.

## When sync runs

| Event | Behaviour |
| --- | --- |
| App start, after the connection is confirmed | One pass if signed in |
| Economy change: completed puzzle, hint, reward, purchase, research, theme, boost, streak freeze | Pass after 2 seconds |
| Progress change: tutorial, unfinished route, preferences | Pass after 20 seconds, so route edits never trigger uploads |
| App goes to the background | Pass now |
| Connection returns | Pass now |
| Settings → Cloud save → Sync now | Pass now |
| Before a coin-pack purchase | Pass required, or the purchase is blocked |
| Before a coin pack is consumed | Pass attempted. Failure does not block consumption |

Passes are serialized. Failures retry after 10 seconds, then 30 seconds, 2 minutes and 5 minutes. Nothing is uploaded per pointer movement.

## How a pass decides

Each pass reads the cloud copy, then compares it with the device copy and with the last state the device agreed with the cloud (the base). The base holds the revision, the economy digest, the payload digest and a hash of the account.

| Situation | Result |
| --- | --- |
| No cloud save | Upload the device save |
| Cloud unchanged since the base, device has changes | Upload |
| Cloud unchanged, device unchanged | Nothing |
| Cloud changed elsewhere, device unchanged | Adopt the cloud copy |
| Cloud and device both changed, economy identical | Merge progress (tutorials and attempts union, play time maximum) and upload |
| Only the device changed economy | Keep the device's coins, take the cloud's progress, upload |
| Only the cloud changed economy | Take the cloud's coins, keep the device's progress, upload |
| Both changed economy | **Ask the player** |
| First sign-in, device has only welcome coins and no results | Adopt the cloud copy |
| First sign-in, device is used, economy differs | **Ask the player** |
| Cloud save unreadable (digest or format mismatch) | Report it. Never overwrite it until the player chooses |

Before any local replacement, the device writes its current save to a backup slot on the device (`pathwise.cloud.backup.v1`). The backup holds one copy, the most recent replacement, and Settings can restore it.

When the player is asked to choose, the dialog shows both copies as facts: coins, hints, levels solved, highest level, and when the cloud copy was saved. The player chooses **Keep this device** (the cloud copy is backed up on the device, then overwritten) or **Use cloud save** (this device's copy is backed up, then replaced).

Account switching clears the base. The next sign-in therefore compares the device with the new account's cloud save, and the rules above apply. A used device is never replaced silently when a different account signs in.

## Conflicts at the storage layer

Saved Games detects concurrent writes. The Android bridge opens snapshots with `RESOLUTION_POLICY_MANUAL`, so another device's write surfaces as a conflict instead of being overwritten. Dart resolves each conflict by writing the cloud's copy back (never by dropping either side), then re-plans. Up to three attempts run per pass.

## Interrupted operations

- **Upload interrupted before the cloud accepts it:** the base stays at the old revision, so the next pass sees the device as changed and uploads again.
- **Upload accepted, process killed before the base is saved:** the next pass finds the cloud's economy equal to the device's and takes the merge branch, which uploads once more without applying anything.
- **Restore interrupted after the backup is written:** the backup exists and the device is unchanged, so the restore can simply be run again.

Planning compares digests, not a history, so no step is applied twice.

## Purchases and the cloud

- A coin pack needs a signed-in account and a successful pass before the store opens.
- The verified grant is saved on the device first (`purchase/<token hash>`), then a pass is attempted, then the purchase is consumed. If the pass fails, consumption still happens, because the grant is durable locally and the next pass uploads it. The alternative, waiting for the cloud, risks Google's acknowledgement deadlines with no real protection, since the local copy is the only record either way.
- Permanent products (Remove Ads, Themes Forever, Premium) are acknowledged and remain restorable through Google Play, not through the cloud save. On each start the app asks Google Play which permanent products the Play account owns and sets the entitlements to match. A refund therefore removes an entitlement even if the cloud save still lists it.
- Premium's 1,000-coin bonus is stored under a fixed ledger ID, so re-verification never pays it twice.

## Guarantees and their limits

Client-managed saves cannot provide the guarantees of a server-authoritative ledger. The design gives these properties:

- A device never overwrites a newer cloud copy with an older one: upload needs the planned base, and Saved Games rejects a write made against a stale copy.
- Economy changed on both sides is never merged automatically, so coins are never added together and a balance is never chosen by size.
- A failed or interrupted operation leaves either the old or the new state, never a partial one.
- Each reward and purchase has a stable ID in the ledger, so an accidental replay of the same event is ignored on this device.

The accepted limitations below are the trade-offs of avoiding a hosted backend:

1. **Modified clients can change local state.** Digests detect corruption and accidental edits; they do not stop a determined user from computing a valid digest. Coins are not tamper-proof.
2. **The cloud save is not an authoritative transaction ledger.** It is the last state a device uploaded. Two devices that are offline at the same time can each spend the same coins locally; the conflict prompt then makes the player choose, which is the only safe outcome without a server.
3. **Consumed coin packs can be lost** if every copy of the save is lost before the cloud accepts it. Google Play no longer lists consumed purchases, so they cannot be rebuilt from Billing alone.
4. **Advertisement rewards are verified on the device.** A modified client can claim a reward. Rewards are limited per day on the device, which only stops accidental over-claiming.
5. **Refund reconciliation is limited to what Google Play reports** when the app starts, plus Google's own purchase history. A refund that happens while a player is offline with the app closed is applied the next time the app starts online.
6. **Device time is not trusted.** Daily rewards and cooldowns use the device clock. Changing the clock can reset a daily limit. Time Attack deadlines use the elapsed-time clock, which does not reset on a clock change.
7. **Going offline does not stop advertisements.** Play requires an internet connection, so a player cannot play offline to avoid ads. Ads themselves can still fail to load, and gameplay never waits for them.

## Debug builds

The debug package has no Play Games project, so debug builds use `FakeCloudSaves` unless `PATHWISE_GAMES_ENABLED=true` is set. The fake keeps its saves under `pathwise.debug.fakecloud.v1`, and the sync base uses `pathwise.debug.cloud.*` keys. Debug and production never share keys, so no test coin grant or test purchase can reach a production save. The fake also supports simulated outages, write conflicts and separate accounts, which the automated tests use.

## Platform scope

Pathwise is Android-only (see [Android-only policy](android-only.md)). Cloud saves use Play Games Saved Games. Other platforms would use `UnsupportedCloudSaves`, which is not built or tested.

## Code map

| File | Role |
| --- | --- |
| `lib/cloud/cloud_save_format.dart` | Envelope, digests, merge rules, sync plan (pure, tested) |
| `lib/cloud/cloud_sync_service.dart` | Serialized passes, base and backup storage, conflict choices |
| `lib/cloud/cloud_save_provider.dart` | Provider interface, Play Games channel client, fake, unsupported stub |
| `lib/cloud/key_value_store.dart` | Small string store for bookkeeping |
| `android/.../CloudSaveChannel.java` | Saved Games calls through Play Games Services v2 |
| `lib/views/cloud_save_section.dart` | Settings section, restore confirmations, conflict dialog |
