# Fortune Wheel

Each spin awards coins. All six wedges occupy 60°.

| Coins | Chance |
| ---: | ---: |
| 8 | 32% |
| 16 | 29% |
| 28 | 21% |
| 48 | 12% |
| 80 | 5% |
| 160 | 1% |

Both spin types select a weighted outcome locally using secure randomness. The earned-reward callback authorizes each bonus draw. The wheel then computes an animation destination centered on the selected wedge. The payout and cooldown are persisted before the animation starts. See setup for device testing.
