# Changelog

## 1.0.0 — First public release line

- Add 13 permanent Research upgrades, eight temporary boosts and collectible supply crates.
- Replace per-puzzle free resets with a persistent shared three-slot hint tank. Coin refills restore three. Each hint after the third on a board requires a separate rewarded ad.
- Expand the Vault to 20 themes and update the Play coin packs to 500, 1,250, 3,000, 7,500 and 18,000 coins.
- Add signed AdMob reward verification for tank refills, extra hints and coins. Raise interstitial spacing to four minutes and require five qualifying exits per opportunity.
- Add Android Play Games v2 authentication, local achievement synchronization, account linking and configured leaderboard viewing. See the publisher guide for activation requirements and integration limits.
- Use Android build code 4 in the repository, subject to the publisher confirming the Play Console artifact history.

Internal development versions follow.


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
