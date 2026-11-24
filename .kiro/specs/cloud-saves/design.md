# Design: Play Games cloud saves, no custom backend

## Decisions

- **Connectivity** (`lib/logic/connectivity_service.dart`). A probe requests Google's connectivity endpoints (`connectivitycheck.gstatic.com/generate_204`, then `www.google.com/generate_204`) and requires HTTP 204. Offline is reported only after two failures at least four seconds apart. Probing pauses in the background. The probe is not a security boundary.
- **Save format** (`lib/cloud/cloud_save_format.dart`). A versioned envelope around the existing device snapshot. Digests cover the whole payload and the economy unit. Economy and progress are split by an explicit key list.
- **Planning is pure** (`planSync`). Nine situations are covered by tests. The only prompt to the player is an economy conflict or a used device signing into an account with different economy.
- **Sync orchestration** (`lib/cloud/cloud_sync_service.dart`). Serialized passes, a persisted baseline (revision, digests, account hash), a backup before every replacement, bounded re-planning on write conflicts, and damaged-save handling.
- **Provider** (`lib/cloud/cloud_save_provider.dart`). `PlayGamesCloudSaves` talks to `CloudSaveChannel.java` over a method channel. Snapshots open in manual-resolution mode, so concurrent writes surface as conflicts. `FakeCloudSaves` serves debug builds and tests. `UnsupportedCloudSaves` serves iOS.
- **Model swap** (`lib/main.dart`). A cloud restore builds a new `AppModel` from the adopted payload and rebuilds the app under a new key. The old model is disposed after the frame.
- **Billing** (`lib/logic/billing_service.dart`). Verification stays on the device (signature with the licensing key). Coin packs are gated on sync. Consumption follows a durable local grant and an attempted sync. Permanent products reconcile against `queryPastPurchases`.
- **Ads** (`lib/logic/ad_service.dart`, restored). Client-side SDK callbacks; `isConnected` comes from the connectivity service.

## Accepted limitations

See `docs/cloud-saves.md#guarantees-and-their-limits`. In short: the cloud save is not a transactional ledger; modified clients can change local state; consumed coin packs can be lost if every copy is lost; refund reconciliation is limited to what Play reports; device time is not trusted.

## Why not Play Integrity or Firebase

Play Integrity verdicts must be decrypted on a server to be trusted. Firebase Authentication and Firestore add a hosted dependency. Neither fits the no-backend requirement.
