# Economy and progression

Pathwise starts with 40 coins. A first Level clear earns 12 coins and its achievement earns another 20, enough for the first 70-coin Coin Magnet rank. A first Daily Challenge clear earns 24 coins. Time Attack pays six coins per solve starting at two solves, up to 48 per session. Research, temporary boosts, and puzzle performance affect eligible gameplay rewards.

Supply crates use their own rarity table and inventory. The Fortune Wheel pays 8, 16, 28, 48, 80, or 160 coins, with a mean of 24.44 coins per spin. Puzzle reward multipliers do not apply to these wheel credits. The three-slot hint tank refills for 16 coins or through a verified ad. Every hint past the third on one puzzle continues to require its own verified ad. [Crates](crates.md) · [Fortune Wheel](fortune-wheel.md) · [Hints](hints.md)

| Permanent catalog | Cost |
| --- | ---: |
| Research, 101 ranks | 367,569 coins |
| Purchasable themes | 128,980 coins |
| Total | 496,549 coins |

Theme prices run from 110 to 60,000 coins, with four free choices. Basin Gold now costs 1,000, Copper Sky costs 4,500, and High Pass costs 12,000. Players retain previously earned themes. All Themes Forever and Premium continue to unlock every theme. See [Research](research.md) and [Boosts](boosts.md) for effects and prices.

## Simulation

Run `dart run tool/economy_simulation.dart` from the repository root. Each profile uses 24 fixed seeds, with assumptions for attendance, play time, solve speed, supply crate collection, boost purchases, and optional ads. The results estimate progression under those assumptions. They are not telemetry or a forecast of video fill rates.

The simulation prints median milestone times, income, balances, and completion percentages. Its crate model includes a catch rate and assumes a verified video is available for participating profiles.

Play Games progress and sharing remain separate from wallet rewards. Internal coin achievements continue to use stable wallet transaction IDs. [Achievement eligibility](google-play-achievements.md)
