# Changelog

## Unreleased

- Add a production illustration library (`assets/art/`: 20 path tips + hero explorer, 8 resource illustrations, 8 UI emblems, and 4 biome landscapes) with `GameAssetCache` for decoded `Canvas` rendering.
- Redesign Home (illustrated campaign hero, Daily Challenge, Time Attack, compact activity tiles), Infinite Campaign Journey (glowing winding trail, medallion nodes, biome headers, and illustrated treasure chests), Fortune Wheel (brass rim, hub medallion, faceted pointer), Completion (removed checkmark circle, unified multiplier track, large 156px bottom-to-top discovery centerpiece without crossing line), Store, Research, Boosts, Achievements, and Streak screens, and remove generic semicircular hills.
- Upgrade visual art direction: add theme-aware `AtmosphericBackdrop` (gradient sky, distant silhouettes, sparse motes), tactile gradient primary buttons, dimensional `GameCard` surfaces, layered continuous route rendering with top-lit highlight and soft glow, dimensional shading and specular highlights on all 20 path tips and resource icons, and a glowing board tray, multiplier track, and progressive discovery aura.
- Stabilize pointer tracking and directional cosmetic rendering: strictly validate cardinal directions against board bounds, walls, gates, arrows, and revisits; preserve the equipped cosmetic across resting, checkpoint, dead-end, and rejection states; add overhead directional silhouettes for `robot` and `ufo`.
- Redesign the completion multiplier track with distinct segments, a game-style pointer, tap-to-stop on the track, and clear bonus coin wording.
- Replace the generic discovery progress bar with `ProgressiveDiscoveryArt` (persisted upcoming collectible identity, bottom-to-top reveal at 10% increments, and clean `Watch to unlock` → `Unlocked!` → `Apply` → `Applied`/`Equipped` transitions).
- Trigger interstitial exit checks on `Next level` transitions, remove the `ads.videoReady` suppression when returning to the menu, and reserve a stable banner ad slot height to prevent layout shifts.
- Improve coin icon contrast against themed buttons, tighten gameplay vertical spacing, and wrap Research and Boost items in `GameCard` containers.

- Open the procedural campaign on a bottom-to-top journey with direct level jumps, solve times and a quick-navigation grid. Remove the 1,000-level progression limit.
- Place a claimable treasure after every finished chapter. Large Play Games snapshots compress for transfer.
- Start the completion multiplier automatically and let the player stop it without ad readiness or connectivity. Cap newly pending coin-only discoveries at one.
- Keep the route tip pointed toward an available unvisited exit at rest, and use separate overhead artwork for several collectibles while dragging.
- Make chapter progress and pending treasures visible on Home. Refresh Research illustrations, boost artwork, coins and chapter chests.

- Game-first UI/UX overhaul. New shared design system (`lib/ui`): flat themed cards, price pills (coin and number only), original vector illustrations, and themed dialogs. Every screen uses palette tokens and was checked on light, dark, warm, cool, AMOLED and High Contrast themes.
- Main menu: a prominent full-width Store card replaces the header bag and the Themes tile; the Wheel is a compact full-width card; the coin balance opens Coins.
- Store: Themes, Tips, Coins and Upgrades under a full-width selector. Themes use board-only thumbnails; Tips show upright art; Coins show a free-coins card with a milestone indicator and coin packs with an unavailable state; Upgrades are illustrated cards.
- All 19 paid tips redrawn as layered vector art with theme-adaptive colours. Prices, IDs and ownership are unchanged.
- Continuous pointer tracking: the tip follows the finger along one cardinal axis, never jumps when a cell is accepted, clamps at walls, gates and wrong checkpoints, and settles on release. Transient state is never persisted.
- Checkpoint tips keep a consistent size, ride the leading rim of the checkpoint disc and keep the number readable.
- Redesigned Levels, gameplay chrome, completion, Time Attack results, Research, Boosts, Wheel, crates, Streak, Statistics, Achievements, Settings, cloud save, hint shop, tutorials and connection screens. Economy, odds, prices, limits, puzzle rules and saves are unchanged.
- Add a screen capture suite (`PATHWISE_CAPTURE_DIR`) and a tip contact sheet.

- Declare Pathwise Android-only. Remove the iOS CI job and iOS verification requirements. The `ios/` directory is kept as dormant scaffolding.
- Replace the custom backend with client-managed cloud saves. Progress syncs through Play Games Services Saved Games, with versioned, digest-checked saves, conservative conflict handling and a backup before every replacement. No server, Firestore or Cloud Run is required.
- Require an internet connection to play. A connectivity service checks a Google connectivity endpoint, pauses the board on connection loss without losing the route, and offers Retry.
- Restore direct Google Play Billing: product availability, pending and cancelled handling, durable grants, and permanent entitlements reconciled against Google Play ownership. Coin packs require a successful cloud sync before purchase.
- Restore client-side AdMob rewards. Each reward instance grants once, after the SDK's earned callback.
- Settings → Cloud save shows account status, sync status, last sync, and offers sign-in, sync, restore and sign-out.
- Android backup is disabled; Saved Games is the recovery mechanism.

- Separate Themes, Store, Wallet and Settings into dedicated destinations. Centralize insufficient-coin dialogs and contextual Store navigation.
- Add a global hint wallet, optional ad rewards and daily milestones, streak freezes, revised prizes, and ad-unlocked Boosts.
- Allow reaching the last checkpoint early and highlight uncovered cells. Keep Time Attack results above the board.
- Add a debug dashboard with isolated persistence and CI coverage for Android debug builds.


- Scope hints and pending hint rewards to puzzle attempts. Replay starts with three, while resume restores usage.
- Add Daily Challenge checkpoints and a floating result card.
- Add 1-, 3-, and 5-minute Time Attack sessions, with separate records, Stop, and Restart.
- Credit earned AdMob rewards locally and retain a durable rolling Fortune Wheel quota.
- Replace shipping purchase verification network calls with platform transaction checks. Add the iOS runner and restore charcoal, white, green, and gold launcher art.
- Reduce entry-level Research, selected theme prices, and Boost costs.


## Gameplay and rewards refinement

- Award supply crates on completion and from accumulated play. Keep unopened crates across restarts.
- Replace the Fortune Wheel with six equal coin wedges, weighted rewards and a precise landing animation.
- Retire Expedition and Field Notes. Preserve accumulated balances, lifetime stats and owned themes. Refund purchases for removed progression upgrades from the saved ledger.
- Redesign Research and Boosts and reduce the Android launcher's central mark by 12%.

## 1.0.0 — First public release line

- Add text-only sharing for Daily Challenge, Time Attack, Expedition, level milestones, achievements and selected Research and theme discoveries. Messages preview real results and the canonical Google Play link before opening Android or a supported destination.
- Add 37 Play Games achievement definitions, including standard, incremental and hidden achievements, durable local progress, account-specific confirmation and an optional native achievements screen. Keep in-game coin rewards separate from remote synchronization. Include a Play Console import workflow and 512 px category icons.
- Add the Fortune Wheel with rolling free and verified video allowances, published odds, and an accessible reveal.
- Expand Research to 151 ranks, add Trail Provisions and a 60-minute coin boost, make High Contrast free, and spread optional themes across early and prestige prices.
- Add Field Notes, a clean-run Expedition achievement, and private on-device economy counters with a manual export.

- Replace Endless with Expedition. Preserve the original three introductory trails and continue into procedurally generated trails with recurring milestones, indexed replay records, and offline resumption.
- Add 13 permanent Research upgrades, eight temporary boosts and collectible supply crates.
- Replace per-puzzle free resets with a persistent shared three-slot hint tank. Coin refills restore three. Each hint after the third on a board requires a separate rewarded ad.
- Expand the Vault to 23 themes and update the Play coin packs to 500, 1,250, 3,000, 7,500 and 18,000 coins.
- Add signed AdMob reward verification for tank refills, extra hints and coins. Raise interstitial spacing to four minutes and require five qualifying exits per opportunity.
- Add Android Play Games v2 authentication, local achievement synchronization, account linking and configured leaderboard viewing. See the publisher guide for activation requirements and integration limits.
- Use Android build code 8 in the repository, subject to the publisher confirming the Play Console artifact history.

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
