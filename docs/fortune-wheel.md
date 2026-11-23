# Fortune Wheel

The Wheel offers one free spin and up to four optional verified video spins in a rolling 24-hour window. Those allowances are independent and together limit one installation to five completed spins. Coins, purchases, Research, Boosts, and Premium do not buy spins. Prizes are virtual and stay in the game.

| Prize | Odds |
| --- | ---: |
| 8 coins | 30% |
| 16 coins | 27% |
| 28 coins | 20% |
| 48 coins | 11% |
| 80 coins | 5% |
| 160 coins | 1% |
| One 2× coin boost lasting 10 minutes | 4% |
| Supply cache containing 20 coins | 2% |

The screen and Cloud Run verifier read the same catalog. Segment angles represent its weights. The app selects or receives the actual prize before animating. Reduced motion skips rotation. The supply cache contains a fixed amount and needs no second roll. Wheel prizes cannot refill the tank or supply extra hints. Boosts never multiply Wheel credits.

## Rolling limits and recovery

The free draw uses secure local randomness and Android elapsed realtime and boot identity. The same atomic snapshot persists the chosen credit or inventory item and the time of the draw. Changing date, time, or zone has no effect. After a reboot the app waits until the new boot has been running for 24 hours, a conservative lower bound on elapsed time. A missing device timing reading pauses eligibility. The free path works offline with a valid reading. Reinstalling without a backup also loses local progression.

An installation's verified video state uses server time. The server validates Google's SSV signature, the dedicated ad unit, and the issued installation-bound ticket. One Firestore transaction claims the receipt, trims timestamps older than 24 hours, enforces four accepted video spins, and draws and credits one prize. Dismissed and failed videos have no signed receipt and yield no credit. One callback cannot pay twice. Production video prizes require SSV, including internal testing.

The server keeps the latest video result, at most four timestamps, and cumulative prize counts. On opening the Wheel after a restart or interrupted response, it returns those counts under the original installation credential. The app checks the cumulative counts and applies the increase once in its local save. The latest prize is used for the matching spin animation. Recovery onto a different installation credential and a server-authoritative offline wallet are outside the current implementation.

## Expected rewards

The free and video spins use identical odds and average **23.60 liquid coins per spin**. The boost has a 4% chance and avoids a 35-coin base purchase if the player would have bought and used it. This contributes up to 1.40 coins per draw in avoided spending at base price. A boost cannot be sold back.

- One draw daily over 30 days averages 708 coins and 1.2 boosts.
- Five draws daily over 30 days average 3,540 coins and six boosts. The maximum possible liquid payout over any rolling 24 hours is 800 coins.
- Maximum wheel ad demand is four rewarded impressions per active day or 120 in 30 days. The optimized profile models seven optional videos per eligible day across the Wheel and the separate three-video coin placement, before optional hint placements. These are demand ceilings rather than AdMob inventory forecasts.
- Wheel boosts provide some of the shortest boosts through ordinary gameplay. Coin income brings forward early Research and cosmetic purchases, but sustained gameplay remains the main funding source for advanced ranks. [Simulation](economy.md)

Publisher configuration includes the dedicated ad unit, SSV test and Firestore retention rules. [Setup](../setup.md#4-before-enabling-advertisements)
