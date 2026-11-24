# Monetization

Production flags default off. See the publisher configuration and device test checklist. [Setup](../setup.md)

| Format | Placement | Eligibility |
| --- | --- | --- |
| Adaptive banner | Level selector and standard puzzle | Configured AdMob unit, UMP permission, adequate height, and no Remove Ads or Premium |
| Interstitial | Exit after completing a Level or Daily Challenge | Five qualifying exits, at least three minutes between impressions, one minute after a rewarded ad, and no active puzzle |
| Rewarded hint | Hint shop | One hint per earned callback, up to five per local day |
| Rewarded coins | Store · Earn Coins | Twenty coins per video, six per day, plus forty on the fourth |
| Rewarded level bonus | Campaign results | First clears with ready video and no competing discovery reveal. Adds only the selected multiplier difference on the base payout. |
| Rewarded discovery | Campaign results and Collections | Durable pending find, claimed only after the earned callback |
| Rewarded boost | Boosts | Three 10-minute 2× Boosts per day; one separate 3× offer after four coin videos |
| Rewarded supply crate | Falling crate dialog | One successful viewing for the displayed amount |
| Rewarded Fortune Wheel | Fortune Wheel | Six video spins per rolling 24 hours, plus the separate free spin |

The Android build template specifies production IDs for five distinct units. Serving is disabled by default. Debug/profile test mode uses Google sample IDs, and the Android release consent-only mode can exercise UMP with production metadata while blocking all ad requests. See [publisher setup](../docs/play-console-setup.md#7-admob-developer).

Client-side AdMob rewards require the SDK earned callback. Placement-specific handlers apply a unique transaction to the local save. Dismissal without earning has no payout. Optional rewards remain available to ad-free purchasers. Local payouts offer weaker tamper resistance than remotely verified receipts.

The Store uses localized Google Play quotes. The app is Android-only. Themes handles palette browsing and unlocks, and the Store header shows the balance. On Android, the app verifies the Play-signed purchase with the configured public key. Fulfillment is saved before consumption or acknowledgement. Premium applies both entitlements and a stable one-time 1,000-coin event per local profile. Consumable recovery after save loss and automatic refund reconciliation are unavailable.
