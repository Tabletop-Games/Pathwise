# Economy and progression

Pathwise starts with 40 coins. A first Level clear earns 12 coins and its achievement earns another 20, enough for the first 55-coin Coin Magnet rank. A first Daily Challenge clear earns 24 coins. Time Attack pays six coins per solve starting at two solves, up to 48 per session. Research, temporary boosts, and puzzle performance affect eligible gameplay rewards.

Supply crates use their own rarity table and disappear when missed. The Fortune Wheel pays 8, 16, 28, 48, 80, or 160 coins, with a mean of 24.44 coins per spin. Puzzle reward multipliers do not apply to these wheel credits. The three-slot hint tank refills for 16 coins or through an earned refill ad. Every hint past the third on one puzzle continues to require its own earned ad. [Crates](crates.md) · [Fortune Wheel](fortune-wheel.md) · [Hints](hints.md)

| Permanent catalog | Cost |
| --- | ---: |
| Research, 101 ranks | 366,144 coins |
| Purchasable themes | 128,900 coins |
| Total | 495,044 coins |

Theme prices run from 90 to 60,000 coins, with four free choices. Basin Gold now costs 1,000, Copper Sky costs 4,500, and High Pass costs 12,000. Players retain previously earned themes. All Themes Forever and Premium continue to unlock every theme. See [Research](research.md) and [Boosts](boosts.md) for effects and prices.

| Item | Old price | New price | Level clears at 12 coins | Purpose |
| --- | ---: | ---: | ---: | --- |
| First Coin Magnet rank | 70 | 55 | 5 | Earlier access to permanent earnings |
| Forest Mint or Warm Walnut | 110 | 90 | 8 | Lower threshold for the first cosmetic |
| Glacier or Midnight Slate | 160 | 140 | 12 | More early palette choices |
| 2× boost, 10 min | 35 | 24 | 2 | Break even after two first clears within the window |
| 2× boost, 15 min | 50 | 36 | 3 | Accessible for a short play session |
| 2× boost, 30 min | 90 | 72 | 6 | Useful for a longer session |
| 2× boost, 60 min | 195 | 150 | 13 | Lower commitment for an extended session |
| 3× boost, 15 min | 110 | 80 | 7 | Break even after four first clears at base reward |
| 4× boost, 10 min | 120 | 88 | 8 | Break even after three first clears at base reward |
| Supply Relay | 35 | 28 | 3 | Lower cost for a chance to catch an extra crate |

## Simulation

Run `dart run tool/economy_simulation.dart` from the repository root. Each profile uses 24 fixed seeds, with assumptions for attendance, play time, solve speed, supply crate collection, boost purchases, and optional ads. The results estimate progression under those assumptions. They are not telemetry or a forecast of video fill rates.

The 24-seed model placed the first coin theme at day 2 and 30 Research ranks at day 89 for the casual profile. The regular profile reached 30 ranks at day 19 and modeled full completion at day 732. The dedicated profile reached those milestones at days 9 and 232, or days 14 and 272 with ads disabled. The model approximates Daily Challenge completion and assumes available videos for eligible participating profiles. These are balance estimates, not observed player results.

Play Games progress and sharing remain separate from wallet rewards. Internal coin achievements continue to use stable wallet transaction IDs. [Achievement eligibility](google-play-achievements.md)
