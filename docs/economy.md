# Economy and progression

Pathwise keeps permanent Research and optional cosmetics as long-term goals. All four modes remain free. Progress begins with 40 coins, 12 on a first Level clear, and 20 for completing the first Level achievement. A first session can therefore buy the 70-coin Coin Magnet rank. A first Daily clear pays 24, and Time Attack retains its six-per-clear payout starting at two, capped at 48 for a session. First trail qualification, field marks, milestone rewards, and personal records provide separate goals. [Expedition](expedition.md)

## Catalog and affordability

The 151 permanent Research ranks cost a combined **1,412,405 coins**. Effects are bounded, prerequisites are disclosed, and only the three ten-rank specialties use the two long-tail costs. The **111,480-coin** purchasable theme catalog spans these tiers.

| Collection | Themes and prices |
| --- | --- |
| Free | Field, Blackwater, Terracotta, High Contrast |
| Everyday | Forest Mint and Warm Walnut for 110, Glacier and Midnight Slate for 160, Oceanic Breeze and Royal Velvet for 220 |
| Premium | Chalk, AMOLED Carbon, Parchment and Lavender Hour for 500, Koi Pond and Retro Terminal for 1,000 |
| Prestige | Painted Canyon for 4,500, Tidal Glass for 12,000, Night Signal for 30,000, Gilded Ink for 60,000 |
| Expedition | Basin Gold at Trail 3, Copper Sky at Trail 25, High Pass at Trail 100 |

Existing ownership is preserved. All Themes Forever and Premium cover all current and future themes. The coin-only permanent catalog target is **1,523,885 coins**. This target excludes optional repeat purchases of boosts and hint refills and the three earned Expedition themes. A tank refill is 16 coins for all players and never substitutes for a fourth puzzle hint. [Research](research.md) · [Boosts](boosts.md) · [Crates](crates.md) · [Wheel](fortune-wheel.md)

Field Notes rotates three objectives at 00:00 UTC from four ordinary gameplay goals. The weekly target is 16 first-time clears and rolls on Monday UTC. Daily rewards start at 9 coins, while weekly rewards are 55. Claims come from completed notes, with one stable claim per period and objective. Progress refuses earlier dates after a rollover. These small offline rewards use the UTC calendar, unlike the Wheel's strict monotonic free-spin window. The app keeps only the active period and a bounded recent reward ledger. Local economy activity uses anonymous event, prize, and balance-band counters, with an optional manual copy action.

## Reproducible simulation

Run `dart run tool/economy_simulation.dart` from the repository root. The model uses 24 fixed seeds for every profile and sensitivity case. Each player has an attendance probability, a session duration, a stochastic solve pace, and a crate collection rate. Calendar days include absences. Mode choices split session time between Levels, Daily, Expedition, and periodic Time Attack. Each video consumes 35 seconds of the session. A profile visits the Wheel once per attended day, at eligible intervals. It claims earned notes and models actual reward odds, crate opportunities, research effects, fixed tank refill costs, boost durations, and the permanent catalog. The model treats qualifying runs as eventual successful progression, uses separate probabilities for first-run field marks, and approximates clean-run achievement timing. It assumes configured ad inventory and does not forecast fill rates or player retention.

Coin packs simulate a 3,000-coin pack approximately every third monthly purchase and a 1,250-coin pack on other purchase days. Premium begins with its coin grant and themes. Those profiles both use strategic boosts, while the basic Regular profile does not. Their difference from Regular combines purchase and play-strategy effects. Gross coins per active hour include bonuses and any paid currency; this figure is a portfolio indicator, rather than a puzzle-only income rate. Median columns are calculated independently.

| Profile | Session | Attendance | Videos | Days to first rank | First coin theme | 30 ranks | Complete coin catalog and Research |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Casual | 18 min | 80% | 0 | 1 | 4 | 50 | 4,391 |
| Regular | 37 min | 90% | 2 | 1 | 2 | 24 | 2,293 |
| Dedicated | 75 min | 96% | 4 | 1 | 1 | 13 | 966 |
| Optimized | 90 min | 99% | 7 | 1 | 1 | 10 | 732 |
| Coin packs | 37 min | 90% | 2 | 1 | 1 | 13 | 1,673 |
| Premium | 37 min | 90% | 2 | 1 | Included | 16 | 1,651 |

Dedicated and optimized free profiles reach the optional completion target in about 2.65 and 2.01 years. The casual horizon is much longer because the final ranks are optional and income grows with attendance, solve rate, and active boost use. Casual players still reach 30 ranks in 50 days. Disabling videos for the same dedicated profile changes full completion from 966 to 993 days. Disabling timed boosts with videos unchanged changes it to 1,251 days. Boosts and first Level clears drive more of the optimized income than video spins. After the final permanent purchase, accumulating spare coins is expected. The model excludes any future catalogs.

## Horizon medians

### Casual

| Day | Balance | Gross earned | Total spent | Coins/hour | Research | Coin themes | Earned cosmetics |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 129 | 4685 | 4567 | 672 | 13% | 38% | 0% |
| 90 | 246 | 15622 | 15226 | 711 | 28% | 63% | 33% |
| 180 | 383 | 34376 | 33940 | 790 | 46% | 63% | 33% |
| 365 | 748 | 85207 | 84909 | 951 | 71% | 75% | 67% |
| 730 | 8834 | 205713 | 199925 | 1167 | 85% | 88% | 67% |
| 1095 | 18172 | 330533 | 309429 | 1255 | 89% | 88% | 100% |
| 1825 | 14782 | 590163 | 588085 | 1346 | 93% | 94% | 100% |

Selected year-one median income sources include levels 25,134, crates 31,507, objectives 11,207, free wheel 6,824.

### Regular

| Day | Balance | Gross earned | Total spent | Coins/hour | Research | Coin themes | Earned cosmetics |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 188 | 10455 | 10112 | 608 | 24% | 38% | 33% |
| 90 | 492 | 33756 | 33460 | 674 | 46% | 63% | 67% |
| 180 | 982 | 79078 | 78629 | 793 | 69% | 75% | 67% |
| 365 | 7004 | 198186 | 197909 | 980 | 85% | 88% | 100% |
| 730 | 15662 | 440544 | 423265 | 1091 | 91% | 94% | 100% |
| 1095 | 25007 | 686610 | 685565 | 1136 | 95% | 94% | 100% |
| 1825 | 54374 | 1198947 | 1144749 | 1187 | 98% | 100% | 100% |

Selected year-one median income sources include levels 68,388, crates 63,855, objectives 16,982, free wheel 7,844, wheel videos 15,428.

### Dedicated

| Day | Balance | Gross earned | Total spent | Coins/hour | Research | Coin themes | Earned cosmetics |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 320 | 22575 | 22232 | 647 | 34% | 63% | 67% |
| 90 | 1275 | 98501 | 96897 | 916 | 74% | 75% | 67% |
| 180 | 9421 | 244929 | 236896 | 1130 | 86% | 88% | 100% |
| 365 | 25209 | 545506 | 511735 | 1249 | 92% | 94% | 100% |
| 730 | 68967 | 1168356 | 1068916 | 1333 | 97% | 100% | 100% |
| 1095 | 228349 | 1815034 | 1586685 | 1384 | 100% | 100% | 100% |
| 1825 | 1484761 | 3112164 | 1626974 | 1423 | 100% | 100% | 100% |

Selected year-one median income sources include levels 320,450, crates 94,314, objectives 21,962, free wheel 8,328, wheel videos 32,836.

### Optimized

| Day | Balance | Gross earned | Total spent | Coins/hour | Research | Coin themes | Earned cosmetics |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 336 | 32981 | 32672 | 735 | 44% | 63% | 67% |
| 90 | 3171 | 142760 | 138360 | 1066 | 81% | 81% | 100% |
| 180 | 15122 | 332468 | 315152 | 1249 | 89% | 88% | 100% |
| 365 | 35696 | 741669 | 701974 | 1362 | 95% | 94% | 100% |
| 730 | 133432 | 1564756 | 1413381 | 1446 | 99% | 100% | 100% |
| 1095 | 823792 | 2414160 | 1589860 | 1487 | 100% | 100% | 100% |
| 1825 | 2480329 | 4111918 | 1632952 | 1522 | 100% | 100% | 100% |

Selected year-one median income sources include levels 467,726, crates 115,811, objectives 23,831, free wheel 8,644, wheel videos 34,204.

### Coin packs

| Day | Balance | Gross earned | Total spent | Coins/hour | Research | Coin themes | Earned cosmetics |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 210 | 16607 | 16556 | 973 | 28% | 63% | 33% |
| 90 | 243 | 51415 | 51358 | 1032 | 54% | 75% | 67% |
| 180 | 1965 | 125011 | 123341 | 1236 | 79% | 75% | 67% |
| 365 | 14293 | 297863 | 291648 | 1466 | 88% | 88% | 100% |
| 730 | 37984 | 641962 | 602619 | 1588 | 93% | 94% | 100% |
| 1095 | 26174 | 996325 | 973066 | 1645 | 97% | 100% | 100% |
| 1825 | 156290 | 1741414 | 1583785 | 1720 | 100% | 100% | 100% |

Selected year-one median income sources include levels 117,896, crates 69,090, objectives 18,343, free wheel 7,844, wheel videos 15,428, coin packs 23,750.

### Premium

| Day | Balance | Gross earned | Total spent | Coins/hour | Research | Coin themes | Earned cosmetics |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 253 | 14611 | 14280 | 851 | 30% | 100% | 100% |
| 90 | 498 | 46258 | 45922 | 936 | 54% | 100% | 100% |
| 180 | 2225 | 113918 | 111205 | 1141 | 78% | 100% | 100% |
| 365 | 13356 | 274170 | 270121 | 1353 | 88% | 100% | 100% |
| 730 | 39238 | 598645 | 551572 | 1487 | 93% | 100% | 100% |
| 1095 | 68642 | 935186 | 861652 | 1541 | 97% | 100% | 100% |
| 1825 | 170819 | 1642824 | 1472262 | 1624 | 100% | 100% | 100% |

Selected year-one median income sources include levels 117,072, crates 68,469, objectives 18,286, free wheel 7,844, wheel videos 15,428.

## Achievement rewards

Pathwise coin achievements are fulfilled by the game wallet and existing transaction identities. Play Games progress and confirmation are independent of coin rewards. Sharing an achievement adds no coins. [Google Play achievement eligibility](google-play-achievements.md)
