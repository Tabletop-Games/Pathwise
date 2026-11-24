# Development guide

- Work in Tabletop-Games/Pathwise and preserve its history. The Chess repository is a read-only GPL-3.0 reference. Keep upstream attribution and bundled font notices.
- Put domain rules in `lib/logic` and app commands and persistence coordination in `AppModel`. Keep views declarative and route visual settings through `BoardPalette`. Keep pointer-only updates inside the board's repaint layers.
- Use named, deterministic puzzle fixtures. Treat existing seed, generation behavior, checkpoint ordering, and saved identifiers as compatibility contracts. Introduce a new puzzle generation version for changed boards and preserve saved boards.
- Persist a completion, its rewards, and any advancement in a single versioned snapshot. Use stable event identities for rewards, spends, and payment fulfillment. Keep save versioning and atomic reward mutations explicit. Internal prerelease paid-hint credits are intentionally discarded.
- Keep theme and reward prices in `lib/model/economy.dart`. Validate new palette text contrast and test both locked and owned states.
- Run `dart format .`, `flutter analyze`, `flutter test`, and `npm --prefix backend test`. Run the Android release checks from [the release guide](../docs/release.md). Verify merged manifests, bundle validity, R8 mapping output, and resource shrinker output.
- Keep monetization flags off by default. Use the Play internal track and AdMob test units before enabling live services. Never put a Play service account key, signing key, or receipt token in this repository.
- Preserve R8 optimization. Add a keep rule only for a diagnosed reflection problem, scope it to the required class/member, then test the minified artifact.

- Keep Time Attack deadlines tied to Android elapsed time and boot identity. Persist the hint wallet separately from per-attempt usage, and never deliver an ad-funded reward from a dismissal, error, or load callback.

- Android startup holds the native launch screen until the saved-theme home screen can render. Verify the native launch and transition when changing startup resources.
- Android updates are checked on demand from Settings using in_app_update_flutter and Google Play. Keep update prompts out of active gameplay and handle unavailable Play services.
