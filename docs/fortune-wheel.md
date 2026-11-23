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

Both spin types select a weighted outcome locally using secure randomness. The earned-reward callback authorizes each bonus draw. The wheel then computes an animation destination centered on the selected wedge. The cooldown and selected prize are persisted before the animation starts. The wallet is credited when the wheel stops. Reopening resumes presentation of an interrupted spin with the same prize. See setup for device testing.

One free spin and six earned video spins are available per rolling 24 hours. The weighted expectation is 24.75 coins per spin and 173.25 across seven spins.
