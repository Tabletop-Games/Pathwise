# Economy

The authoritative values are in `lib/model/economy.dart` (`EconomyRules`, tips, themes, achievements, mystery weights) and `lib/model/progression.dart` (Research, Boosts, crates). This file explains how they fit together. When you change a value, change the code, this file and the affected tests together. Do not rebalance as a side effect of other work.

All coins live in one local ledger (`Wallet`). Every credit and debit has a stable ID, so a reward or purchase applies once. See [cloud-saves.md](cloud-saves.md) for how the economy syncs.

## Earning

| Source | Amount |
| --- | --- |
| New profile | 50 coins and 3 hints |
| First campaign clear | `(5 + stars) × boost multiplier`, plus Research bonuses |
| First Daily Challenge board clear | `10 × boost multiplier`, plus Research bonuses |
| Time Attack | 3 coins per solve, paid from the second solve, capped at 24 |
| Coin video | 20 coins, up to 6 per local day; the 4th adds 40 once per day |
| Completion video (campaign) | The difference up to the chosen 2×/3×/4× on the clear's earned coins, once per level |
| Chapter treasure | 25 coins and 1 hint, free |
| Mystery reward | Every 10th first campaign clear: coins (25–100), a boost, a tip or a theme; claimed with a video |
| Supply crate | 20, 35, 55, 75 or 90 coins (35/30/20/10/5 %); see below |
| Fortune Wheel | 8, 15, 25, 40, 70 or 100 coins (30/25/20/15/8/2 %); one free spin per 24 h, plus video spins |
| Daily streak | Day 1/3/7/14/30/60/100/150/200 pay 20/50/100/200/400/600/1,000/1,200/1,500 coins and 0/0/1/1/2/2/3/3/3 hints; every 7th day also pays 25 coins plus Research |
| Achievements | 14 achievements, 20–500 coins each, paid once |
| Coin packs, Premium | Real-money purchases through Google Play ([monetization.md](monetization.md)); Premium also pays 1,000 coins once |

The boost multiplier applies to the base and star part of a clear. Research bonuses are added after and are not multiplied. Replays never repeat first-clear rewards.

Rewarded video limits are intentionally few. The only per-day cap is 6 coin videos. Hint videos, boost videos and wheel video spins have no local daily cap, so Google's own ad availability and the reward-day anti-rollback check limit them. The 3× Power Surge boost video unlocks once per day after the fourth coin video. Every rewarded payout requires the SDK's earned callback, applies once per reward instance, and is persisted before the player sees it.

## Spending

| Item | Price |
| --- | --- |
| Hint | 80 coins, or one rewarded video |
| Streak Freeze | 300 coins, inventory limit 2 |
| Themes | Free: Field, Blackwater, Terracotta, High Contrast. Others 120–6,000 coins by tier (see `EconomyRules.themePrice`). "Themes Forever" unlocks all. |
| Tips | Classic is free. Common 240, Uncommon 500, Rare 1,000, Epic 1,800 coins (see the `PathTip` enum). |
| Research | `base × (rank + 2) × (rank + 3) ÷ 6` per rank; advanced specialties use a fixed multiplier table. |
| Boosts | 60–160 coins before Research discounts. |

Previewing never purchases or equips. Buying writes one ledger debit and the ownership in a single save. Apply is a separate action.

## Research

Ranks are permanent and bought with coins. Prices follow the curve above with each family's `base`; the three specialties require rank 3 of a prerequisite.

| Research | Effect per rank | Max rank |
| --- | --- | ---: |
| Coin Magnet | +1 coin on a first level clear | 10 |
| Golden Route | +1 coin on a hint-free first clear | 8 |
| Daily Fortune | +2 coins on a first daily clear | 8 |
| Milestone Mastery | +3 coins on newly earned achievements | 6 |
| Treasure Hunter | −3 s between crate offers | 8 |
| Crate Collector | +1 s crate flight time | 9 |
| Boost Efficiency | +2 % boost duration | 8 |
| Smart Savings | +1 % boost price discount | 6 |
| Momentum | +2 coins at every fifth first clear | 8 |
| Daily Specialist | +5 coins on each seven-day streak award | 6 |
| Boost Tuning (needs Boost Efficiency) | +1 % duration | 8 |
| Contract Supply (needs Smart Savings) | +1 % discount | 8 |
| Supply Routes (needs Treasure Hunter) | −2 s between crate offers | 8 |

## Boosts

One coin multiplier can be active at a time. Durations are extended by Research. Boosts are bought with coins or earned, enter the inventory, and are activated from the Boosts screen. Only puzzle-clear earnings are multiplied.

| Boost | Effect | Minutes | Coins | Video |
| --- | --- | ---: | ---: | --- |
| Quick Charge | 2× | 5 | 60 | Yes |
| Endurance | 2× | 15 | 160 | — |
| Power Surge | 3× | 5 | 130 | Once per day after four coin videos |
| Royal Rush | 4× | 3 | 150 | — |

Mystery rewards can also grant Quick Charge, Endurance, Power Surge or Royal Rush.

## Supply crates

Campaign and Daily play offer a falling crate after 45 s of foreground play and then roughly every 150 s (reduced by Research), with at most 8 offers per rolling 24 hours. The prize is fixed when the crate spawns and the crate disappears if missed. Tapping opens a reward dialog; claiming needs one rewarded video, and dismissing forfeits the crate.

## Fortune Wheel

Six equal wedges. The weighted prize is chosen locally with secure randomness, the cooldown and prize are persisted before the animation starts, and the wallet is credited when the wheel stops. Reopening resumes an interrupted spin with the same prize. The free spin refreshes every 24 hours on the elapsed-time clock.

## Ads

| Format | Rule |
| --- | --- |
| Banner | Standard puzzle only, adaptive, hidden for Remove Ads and Premium |
| Interstitial | After 5 completed exits from a campaign or Daily puzzle, at least 3 minutes apart and 1 minute after a rewarded ad, never during play |
| Rewarded | Hint, coins, boost, crate, wheel, completion multiplier, mystery reward |

Optional rewarded videos remain available to ad-free players.

## Simulation

`dart run tool/economy_simulation.dart` produces seeded scenario estimates under declared assumptions (play time, attendance, puzzle speed, video take-up, spending). `dart run tool/journey_economy.dart` isolates the campaign rewards. These are estimates, not forecasts, and CI runs the first as a regression check.
