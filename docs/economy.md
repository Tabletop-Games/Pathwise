# Economy

Welcome balance is 40 coins. First level clears earn 12 and daily clears earn 24. A seven-day streak earns 35, with research bonuses where applicable. Local Time Attack pays six per clear starting at two clears, capped at 48 per run. Achievements grant 20–500 once. Optional rewarded coin videos grant eight, up to three per local day. Ordinary replays have no base clear reward. [Expedition](game-modes.md#economy-and-integrity) pays at most 60 milestone coins per trail, plus a one-time Field Guide achievement. See [Research](research.md), [Boosts](boosts.md), [crates](crates.md) and the [hint tank](hints.md).

The Vault has three free palettes. Paid prices are 110 for Forest Mint and Warm Walnut, 160 for Glacier and Midnight Slate, 220 for Oceanic Breeze and Royal Velvet, 500 for Chalk, AMOLED Carbon, Parchment, Lavender Hour and High Contrast, 1,000 for Canyon, Tidal, Koi Pond and Retro Terminal, and 1,500 for Neon and Gilded Ink. The Vault displays localized Play prices for the [eight products](../setup.md#3-before-enabling-purchases).

## Deterministic model

Run `dart run tool/economy_simulation.dart`. The model assumes one eligible daily solve per session, first-clear levels only, and 70% collection of available crates at their base odds. It excludes future achievements, researched income, time spent in menus or viewing ads, and spend. Coin/hour figures normalize one session and are constrained by the six crate opportunities per day. They are not indefinite production rates. Unlock estimates are linear budget estimates after welcome coins and the first-level achievement.

| Profile | Minutes | Level clears | Coins per active hour | Estimated first research | Estimated first paid theme |
| --- | ---: | ---: | ---: | ---: | ---: |
| Casual, no ads | 15 | 4 | 595 | 1.0 min | 5.0 min |
| Average, no ads | 30 | 10 | 442 | 1.4 min | 6.8 min |
| Engaged, no ads | 60 | 25 | 401 | 1.5 min | 7.5 min |
| Average, three optional ads | 30 | 10 | 490 | 1.2 min | 6.1 min |
| Average, Starter purchase | 30 | 10 | 442 gameplay | Immediately | Immediately |

The initial 70-coin Magnet rank breaks even after 35 unboosted level clears. Full research costs 76,925 coins, equivalent to about 174 hours at the fixed 442-coins/hour reference before compounding and spend. Five coin boosts require 3, 5, 8, 5 and 4 eligible first level clears respectively to break even at base earnings. Crates average 18.30 coins per offer and contribute up to about 77 coins per day at the modeled collection rate before research. Research increases inflow in bounded ranks. Late-play net holdings depend on boost use, repeated play and purchases and need observation on an internal test cohort.

At illustrative USD prices the five packs deliver about 505, 628, 752, 939 and 1,126 coins per dollar. Actual pricing comes from Google Play.
