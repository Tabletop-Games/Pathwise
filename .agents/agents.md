# Development guide

- Pathwise is Android-only. Do not build, compile, sign, test or investigate iOS. See [the Android-only policy](../docs/android-only.md).
- Work in Tabletop-Games/Pathwise and preserve its history. The Chess repository is a read-only GPL-3.0 reference. Keep upstream attribution and bundled font notices.
- Pathwise has no custom backend. Do not add a hosted service, Firestore, Cloud Run or custom API endpoints. Progress syncs through Play Games Saved Games (see `docs/cloud-saves.md`). The archived server-authoritative implementation is on the branch `archive/server-authoritative-backend`.
- Put domain rules in `lib/logic` and `lib/cloud` (pure rules are unit-tested), feature presentation logic in `lib/viewmodels` (widget-free, `BuildContext`-free), app commands and persistence coordination in `AppModel`, and sync orchestration in `CloudSyncService`. Keep views declarative and route visual settings through `BoardPalette`. Keep pointer-only updates inside the board's repaint layers.
- Keep `lib/logic`, `lib/cloud`, and pure `lib/model` free of upward dependencies on `AppModel`, `lib/views`, or `lib/ui`; verify with `test/architecture_boundaries_test.dart`.
- Use named, deterministic puzzle fixtures. Treat existing seed, generation behavior, checkpoint ordering, and saved identifiers as compatibility contracts. Introduce a new puzzle generation version for changed boards and preserve saved boards.
- Persist a completion, its rewards, and any advancement in a single versioned snapshot. Use stable event identities for rewards, spends, and payment fulfillment. Keep save versioning explicit. The cloud envelope uses its own version; change `cloudSaveVersion` and add a migration when the payload's shape changes.
- Economy changes belong to the economy unit in `lib/cloud/cloud_save_format.dart`. Progress-only keys belong to `progressKeys`. Never merge economy automatically; ask the player when both devices changed it.
- Keep theme and reward prices in `lib/model/economy.dart`. Validate new palette text contrast and test both locked and owned states.
- Every gameplay path must respect the internet requirement (`AppModel.onlineReady`). Do not send network requests per tile movement.
- Run `dart format .`, `flutter analyze`, `flutter test` and `dart run tool/economy_simulation.dart`. Run the Android release checks from [the release guide](../docs/release.md). Verify merged manifests, bundle validity, R8 mapping output, and resource shrinker output.
- Keep monetization flags off by default. Use the Play internal track and AdMob test units before enabling live services. Never put a signing key, service-account credential, or purchase token in this repository.
- Preserve R8 optimization. Add a keep rule only for a diagnosed reflection problem, scope it to the required class/member, then test the minified artifact.
- Keep Time Attack deadlines tied to Android elapsed time and boot identity. Persist the hint wallet separately from per-attempt usage, and never deliver an ad-funded reward from a dismissal, error, or load callback.
- Android startup holds the native launch screen until the saved-theme home screen can render. Verify the native launch and transition when changing startup resources.
- Android updates are checked on demand from Settings using in_app_update_flutter and Google Play. Keep update prompts out of active gameplay and handle unavailable Play services.
