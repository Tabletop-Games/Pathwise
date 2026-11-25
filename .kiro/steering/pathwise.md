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

## Quiet Journey

- Design for a relaxing Android puzzle game. Put the campaign and the board first, use open layouts and give each screen its own composition. Shared controls must not turn screens into grids of identical cards and pills.
- Use quiet landscape vector art, accent colors drawn from the equipped palette, and restrained motion. Keep high contrast and AMOLED views clear of atmospheric decoration.
- Completion bonuses multiply only the configured base campaign payout. Credit only the difference from the earned SDK callback using one ledger ID per level. Replays and other modes cannot earn the bonus.
- Ten prospective first clears reveal one unowned, unreserved cosmetic from the configured catalogue. Keep discoveries pending indefinitely and grant the fallback when exhausted or already owned. Equip only on an explicit action.

## Field Notes artwork

- Review [Visual identity](../../docs/visual-identity.md) and its reference sheet before creating assets. Keep functional marks, collectible silhouettes and chapter illustrations distinct.
- Use layered silhouettes, optical sizing and muted, palette-aware colour. Review new artwork on its actual board and at catalogue scale. Avoid heavy outlines, exaggerated faces, generic badges and decorative chart-like UI.
- Derive any new art from the shared vector families under `lib/ui/art/`. Decorative changes must preserve the hit targets, reward timings and persisted identifiers that the art represents.

## Endless campaign and results

- The procedural campaign is unbounded. Keep generation identity stable and derive chapter metadata on demand.
- Show the journey bottom to top with lazy rendering and direct positioning. Keep the compact grid as an alternate level selector.
- Keep earned chapter chests claimable. Grant the free reward once using the wallet transaction and commit the corresponding hint in the same save.
- Start the completion multiplier independently of ad or network state. Request a video only on claim. Award the difference on the configured base reward after the SDK confirms it.
- Choose the resting tip's cardinal direction with ordinary local movement validation. Use a neutral pose where there is no unvisited exit. Never consult the solver or replace the active pointer projection.
- Keep Android as the sole supported platform. Preserve the local and Play Games architecture, existing purchases and entitlements.
- Keep Pathwise's visual layouts compact, varied and legible. Use deliberate focal points and inspect rendered compositions at real game scale.
