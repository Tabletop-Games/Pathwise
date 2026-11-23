# Economy and progression

Pathwise starts with 40 coins. A first Level clear earns 12 coins and its achievement earns another 20, enough for the first 70-coin Coin Magnet rank. A first Daily Challenge clear earns 24 coins. Time Attack pays six coins per solve starting at two solves, up to 48 per session. Research, temporary boosts, and puzzle performance affect eligible gameplay rewards.

Supply crates use their own rarity table and inventory. The Fortune Wheel pays 8, 16, 28, 48, 80, or 160 coins, with a mean of 24.44 coins per spin. Puzzle reward multipliers do not apply to these wheel credits. The three-slot hint tank refills for 16 coins or through a verified ad. Every hint past the third on one puzzle continues to require its own verified ad. [Crates](crates.md) · [Fortune Wheel](fortune-wheel.md) · [Hints](hints.md)

| Permanent catalog | Cost |
| --- | ---: |
| Research, 131 ranks | 672,155 coins |
| Purchasable themes | 128,980 coins |
| Total | 801,135 coins |

Theme prices run from 110 to 60,000 coins, with four free choices. Basin Gold now costs 1,000, Copper Sky costs 4,500, and High Pass costs 12,000. Players retain previously earned themes. All Themes Forever and Premium continue to unlock every theme. See [Research](research.md) and [Boosts](boosts.md) for effects and prices.

## Simulation

Run `dart run tool/economy_simulation.dart` from the repository root. Each profile uses 24 fixed seeds, with assumptions for attendance, play time, solve speed, supply crate collection, boost purchases, and optional ads. The results estimate progression under those assumptions. They are not telemetry or a forecast of video fill rates.

| Profile | First Research rank | First coin theme | 30 ranks | Full permanent coin catalog |
| --- | ---: | ---: | ---: | ---: |
| Casual | 1 day | 3 days | 45 days | 1,948 days |
| Regular | 1 day | 2 days | 21 days | 988 days |
| Dedicated | 1 day | 1 day | 10 days | 360 days |
| Optimized | 1 day | 1 day | 7 days | 270 days |
| Coin packs | 1 day | 1 day | 11 days | 685 days |
| Premium | 1 day | Included | 14 days | 609 days |

The dedicated profile reached the full catalog in a median 372 days with ads disabled, or 507 days with timed boosts disabled. The tool also prints income, balances, spending and completion percentages at 30, 90, 180, 365, 730, 1,095 and 1,825 days.

Play Games progress and sharing remain separate from wallet rewards. Internal coin achievements continue to use stable wallet transaction IDs. [Achievement eligibility](google-play-achievements.md)
