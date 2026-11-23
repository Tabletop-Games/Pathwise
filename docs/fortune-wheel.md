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

The free spin uses a secure random draw. Rewarded spins use the backend's secure random draw after AdMob server-side verification. Both read the same catalog. The wheel calculates a destination at the winning wedge's center, adds five full rotations, and reveals the result. Reduced motion aligns the wheel immediately. The wallet commit happens independently of the animation. Closing the screen does not reset the cooldown or repeat a credit. In-app chances are available in Settings under **Reward information**.

The free spin has a rolling, 24-hour elapsed-time cooldown and works offline. The optional video button appears only when a video is ready and the server confirms at least one of four rolling opportunities remains. The backend serves catalog version 2. Deploy it before testing the current app's rewarded spins. The app carries forward previously saved receipt counts. A previously verified but unclaimed legacy boost settles at 35 coins, and a legacy cache settles at 20 coins. Each previously claimed receipt keeps its original result. The mean of the new distribution is 24.44 coins per spin.
