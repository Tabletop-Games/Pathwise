# Tasks

## Implemented (automated tests in `test/`)

- [x] Archive the server-authoritative backend on `archive/server-authoritative-backend`.
- [x] Remove the backend, its deployment files, its CI job and its build variables.
- [x] Connectivity service with confirmed-failure rules (`connectivity_test.dart`).
- [x] Internet requirement in `AppModel`: no puzzle starts offline, the route is kept, input is refused, purchases, rewards and the wheel are blocked (`connectivity_test.dart`).
- [x] Connection gate and overlay (`views/connection_view.dart`).
- [x] Cloud save envelope, digests and merge rules (`cloud_save_format_test.dart`).
- [x] Sync planning table (`cloud_save_format_test.dart`).
- [x] Serialized sync, interrupted upload, write conflict, damaged save, account switch, backup and restore, urgent and debounced triggers (`cloud_sync_service_test.dart`).
- [x] Persistent fake provider for debug builds and tests.
- [x] Provider selection (unsupported platforms); debug isolation (`cloud_guard_test.dart`).
- [x] Entitlement reconciliation against Play ownership; Premium bonus and token dedupe; ad reward dedupe; daily ad limits (`cloud_guard_test.dart`).
- [x] Play Games Saved Games bridge (`CloudSaveChannel.java`), registered in `MainActivity`.
- [x] Settings → Cloud save section and conflict dialog.
- [x] Android backup disabled.
- [x] Documentation: cloud saves, connectivity, Play Console and AdMob guide, security, setup, architecture, agent guides, changelog.
- [x] CI: backend steps removed.

## Manual (cannot be completed from the repository)

- [ ] Create and configure the Play Games Services project, enable Saved Games, and add testers (`docs/play-console-setup.md` §3).
- [ ] Set `PATHWISE_GAMES_PROJECT_ID` and `PATHWISE_GAMES_ENABLED` for the release build.
- [ ] Create the eight products and the licensing key; add license testers (§5).
- [ ] Upload an internal-testing release and confirm the AdMob settings (§6, §7).
- [ ] Run the device verification checklist (§9): cross-device sync, conflict dialog, reinstall recovery, airplane-mode overlay, purchase and refund.
