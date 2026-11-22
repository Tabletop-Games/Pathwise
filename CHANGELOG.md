# Changelog

## 1.2.0

- Added offline Time Attack with a ten-minute Android monotonic clock, automatic progression, scores, records, and capped rewards.
- Added progressive, persisted hints and separate extra-hint routes through optional rewarded video or coins for ad-free players.
- Added adaptive banners, centralized interstitial pacing, optional coin-video confirmations, and separate permanent Remove Ads and Premium products. Retained the permanent all-theme pass.
- Expanded the cosmetic catalog and responsive Levels grid. Added standard, adaptive, and themed launcher artwork and a matching Play listing icon.
- Migrated to save schema 3 while retaining existing progression, puzzle seeds, balance, themes, and verified entitlements.

## 1.1.0

- Expanded the campaign to deterministic, ongoing progression with unique solutions. Added a horizontal twelve-level grid with locked, current, and completed states, best times, replay, and direct continuation. Existing boards and progress retain their identifiers.
- Added Pathwise Coins, a transaction ledger, first-clear and streak rewards, and seven achievements. Added a cosmetic store with live previews, purchase confirmation, and six new themes.
- Redesigned results to show completion time, personal best, reward, balance, and navigation. Added longest streak, total play time, unlocked level, and economy totals to statistics.
- Added optional Play Billing and AdMob infrastructure, including backend receipt verification, durable deduplication, localized prices, and consent-gated ad loading. Production services ship disabled without valid configuration.
- Extended the save schema while preserving v1 routes, completion records, themes, and preferences. Optimized pointer rendering and made Android release code and resource shrinking explicit.

## 1.0.0

- Initial offline Android release with 36 levels, daily and endless puzzles, three themes, local statistics, and persistent progress.
