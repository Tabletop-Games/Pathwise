# Pathwise working rules

- Pathwise is Android-only. See `.kiro/steering/android-only.md` and `docs/android-only.md`.

- There is no custom backend. Do not add Cloud Run, Firestore, custom APIs or backend-issued identities. Progress syncs through Play Games Saved Games (`docs/cloud-saves.md`).
- Gameplay needs a confirmed internet connection through `ConnectivityService`. Do not add per-screen network checks.
- Economy and progress live in the device save and the cloud envelope. Economy that changed on both sides is never merged automatically.
- Keep `progressKeys` in `lib/cloud/cloud_save_format.dart` in step with what counts as progress. Bump `cloudSaveVersion` when the payload shape changes.
- Run `dart format .`, `flutter analyze` and `flutter test` before committing. Analyzer infos fail CI here.
- The archived backend is on `archive/server-authoritative-backend`. Do not restore it to `main`.


## UI principles

- Pathwise is Android-only and has no hosted backend. Saves sync through Play Games Saved Games.
- The game comes first: keep the board large, remove permanent instruction text, and keep chrome tight.
- Show, don't explain. Prefer icons, numbers and art to sentences. Keep essential disclosures (purchase terms, rewards, limits) reachable behind a Details action.
- Use original vector art drawn in code (`lib/ui/game_art.dart`, `lib/views/components/tip_art.dart`). No emojis and no Material icons as cosmetic art. Material icons are fine for plain controls.
- Colour comes from the equipped `BoardPalette` through `context.palette` and the `GameColors` tokens. Never hard-code colours. Check light, dark, warm, cool, AMOLED and High Contrast.
- Use the shared widgets in `lib/ui/game_ui.dart`: `GameCard`, `PricePill` (coin and number only), `ActionPill`, `GameSegmented`, `GameBar`, `RewardAmount`, `BalanceChip`, `GameDialog`.
- Layouts must survive 320dp wide and 1.5x text. Scale or wrap instead of overflowing.
- Pointer tracking lives in `lib/logic/tip_tracker.dart`: cardinal-only, no jump on cell acceptance, transient state never persisted.
- Test visually: `test/ui_captures_test.dart` renders every screen on six themes and several viewports; set `PATHWISE_CAPTURE_DIR` to write PNGs and inspect them.
