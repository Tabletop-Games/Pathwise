# Design system

The rules for how Pathwise looks and behaves live in the repository skill [`.agents/skills/pathwise-design`](../.agents/skills/pathwise-design/SKILL.md). Load it before substantial UI work. This page records what exists in the code so the skill and the code stay aligned.

## Identity in one paragraph

A polished, illustrated mobile puzzle game: a large board and a campaign path in front, quiet flat surfaces behind, and dimensional collectible and scenery artwork carrying the colour. Bricolage Grotesque is the only typeface. Every colour comes from the equipped theme.

## Where things are

| Concern | Location |
| --- | --- |
| Palettes and themes (23, including AMOLED and High Contrast) | `lib/model/app_themes.dart`, `lib/model/user_preferences.dart` (`PathwiseTheme`) |
| Tokens, shared widgets, dialogs | `lib/ui/game_ui.dart` (`GameTokens`, `GameCard`, `PricePill`, `ActionPill`, `GameSegmented`, `GameBar`, `ProgressPips`, `RatingStar`, `BalanceChip`, `RewardAmount`, `InfoChip`, `GameDialog`) |
| Illustration lookup and image cache | `lib/ui/art/game_assets.dart`, `lib/ui/game_art.dart` |
| Control glyphs | `lib/ui/art/control_art.dart` |
| Tip artwork and board tip rendering | `lib/views/components/tip_art.dart`, `lib/views/components/puzzle_board.dart` |
| Tip tracking | `lib/logic/tip_tracker.dart` |
| Journey scenery | `lib/views/journey_landscape.dart`, `lib/views/campaign_journey_view.dart` |
| Bundled artwork | `assets/art/` (tips, resources, ui, biomes, journey) |
| Google Play listing art (not bundled) | `docs/media/pathwise-feature-graphic.png`, `docs/media/pathwise-play-icon.png`, `docs/media/play-games/` |
| Sound effects | `assets/audio/`, `lib/logic/sound_service.dart` |
| Haptics | `lib/logic/haptic_service.dart` |

## Themes and accessibility

`test/model/theme_contrast_test.dart` checks every palette in `PathwiseTheme.values`. Text must reach 4.5:1 and meaningful graphics 3:1 against the colour actually behind them. Cosmetic artwork in the Store and collections is shown as it is; only the tip on the board gets a contrast halo, and only on the High Contrast and AMOLED themes.

## Visual regression

`test/widgets/ui_captures_test.dart` renders the main screens on six reference themes and at several viewports and text scales, and fails on overflow. Run it with `PATHWISE_CAPTURE_DIR=/path flutter test test/widgets/ui_captures_test.dart` to write PNGs, then look at them. Artwork transparency and references are checked by `test/architecture/asset_validation_test.dart`.

## Attribution

The Bricolage Grotesque font keeps its SIL Open Font License notice (`assets/fonts/OFL.txt`), registered in `lib/main.dart`. The project is distributed under GPL-3.0 and adapts structure from [shenmareparas/Chess](https://github.com/shenmareparas/Chess); keep the attribution in the README.
