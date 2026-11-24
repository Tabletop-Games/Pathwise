# Requirements: Play Games cloud saves, no custom backend

Source: the developer's brief of this change. Scope decisions are recorded in design.md.

1. Pathwise runs with no hosted backend. No Cloud Run, Firestore, custom API, custom sessions or backend-issued identities.
2. Ordinary gameplay requires a confirmed internet connection, for free and paid players. Reachability is checked against an endpoint that does not belong to the developer. A Wi-Fi connection alone is not enough.
3. Connection loss pauses play safely: the route, checkpoints and mechanic state are kept, no new puzzle starts, the timer stops, a themed overlay is shown, and play resumes in place when the connection returns. Brief drops do not interrupt play. No network request is made per tile.
4. The save is synchronized to Google Play Games Services Saved Games on Android. It contains the economy, progress, streaks, achievements, research, boosts, themes, tutorials, rewards and cooldowns, and the unfinished route. It contains no tokens or identifiers.
5. Sync is versioned, revisioned, serialized, debounced for progress, retried with backoff, and interrupt-safe. It never replaces newer data with older data, never merges economy automatically, and asks the player when economy conflicts.
6. Coin purchases require a recoverable account and a successful sync. Permanent entitlements are reconciled against Google Play ownership. Pending and cancelled purchases are never granted. Grants are durable and deduplicated.
7. Rewarded ads grant each reward once, only after the SDK's earned callback. Remove Ads and Premium remove automatic ads; Themes Forever alone does not.
8. Settings has a Cloud save section with status, sign-in, sync, restore and sign-out, and never shows identifiers or raw errors.
9. Debug and production saves are isolated. Debug builds use a local fake save unless Play Games is enabled for the debug package. iOS compiles and falls back to local saves.
10. The previous backend stays available on the branch `archive/server-authoritative-backend`.
