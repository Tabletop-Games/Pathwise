# Supply crates

The first supply crate becomes eligible after 45 seconds of foreground play in Levels or Daily Challenge. Eligible time accumulates across puzzles and pauses on the results screen, at home, while the crate inventory is open, and in the background. A final move checks eligibility directly. An open puzzle also checks once per second. During a stroke, time accrues without placing a crate in the way.

| Rarity | Base odds | Base coins |
| --- | ---: | ---: |
| Common | 75% | 12 |
| Uncommon | 18% | 25 |
| Rare | 6% | 55 |
| Legendary | 1% | 150 |

Crates have a 150-second base cooldown after each drop. The game allows up to six drops in a rolling 24-hour window using Android elapsed time. After a reboot, device uptime supplies a conservative lower bound. Opening a crate, restarting, or changing the calendar cannot reset the limit.

Earned crates stay in the supply inventory until opened. One slot is available by default. Each Crate Collector rank adds one slot. A full inventory pauses new drops. Treasure Hunter and Supply Routes reduce the cooldown. Lucky Crates, Rare Salvage, Legendary Cache, Rare Discovery, Legendary Discovery, and crate boosts retain their effects.

The app saves the unopened inventory, cooldown and quota in its local snapshot. Opening a crate commits its removal and coin credit together. The crate ID is the wallet transaction key. Existing saves carry over their last recorded unopened crate and take credit for earlier drops when the legacy daily count is available.
