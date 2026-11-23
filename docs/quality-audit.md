# Pathwise quality audit

| Area | Severity | Finding and resolution |
| --- | --- | --- |
| Fortune Wheel | Critical | Drawing and crediting happened together. The app now reserves a fixed prize before presentation, settles it after the wheel stops, and restores pending animation from the saved outcome. |
| Advanced Levels | Critical | Level number previously changed board size and checkpoint density without introducing new rules. Board generation now attaches validated movement constraints and the route controller, solver and renderer use them. |
| Hints | High | Disabled acquisition controls obscured the next action. The compact dialog shows availability, price or shortfall, a direct Wheel route, and an explicit Close action. |
| Time Attack | Medium | Plain duration rows sat in a centered scrolling block. Selected cards are positioned at the top and show the local best for each duration. |
| Themes | Medium | Theme browsing was tucked into Vault and Settings. Home now links straight to Themes with explicit Apply and Buy actions. |
| Android icon | Medium | The adaptive mark had a separate white emblem that consumed its foreground area. The revised vector gives the green route mark more area with a cream line and gold endpoints. |

## Gameplay verification

Use `flutter test` for the complete regression suite. The advanced generation fixture exercises eight seeds at each of 14 progression boundaries and representative levels through 1000. A separate canonical sweep generated and re-solved every Level 1–1000 with a unique solution. The suite checks rewarded-callback deduplication, hint wallet persistence, Freezes, Boost inventory, crate overlays and claim retries, theme previews, wheel cooldown and interruption, and timed game state.

| Levels | Generated rule | Canonical boards |
| --- | --- | ---: |
| 1–20 | Classic | 20 |
| 21–40 | Walls | 20 |
| 41–70 | Directional exits | 30 |
| 71–100 | Keys and gates | 30 |
| 101–150 | Portal pairs | 50 |
| 151–200 | Ice | 50 |
| 201–1000 | Mixed | 800 |

Existing Level records and unfinished boards are marked as classic at migration, so their paths and times remain valid. New levels follow the advanced bands, and the debug explorer can open a generated board in an isolated preview. Daily Challenge and Time Attack use their existing board rules.

Flutter captures are simulated widget renders. Live AdMob inventory, Android launcher masks, and device installation require a configured device or emulator.
