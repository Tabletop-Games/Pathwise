# Fortune Wheel

Each spin awards coins. All six wedges occupy 60°.

| Coins | Chance |
| ---: | ---: |
| 8 | 30% |
| 15 | 25% |
| 25 | 20% |
| 40 | 15% |
| 70 | 8% |
| 100 | 2% |

The server draws both spin types with secure randomness and stores the pending prize and cooldown before the animation starts. A video spin is drawn only after a verified AdMob callback. The wheel animates to the selected wedge, and the coins are credited when the client reports that it stopped. Reopening the app restores an interrupted spin from the server's pending prize. Cooldowns and the rolling video window use server time.

One free spin and six earned video spins are available per rolling 24 hours. The weighted expectation is 24.75 coins per spin and 173.25 across seven spins.
