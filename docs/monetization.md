# Monetization

Production flags default off. See the publisher configuration and device test checklist. [Setup](../setup.md)

| Format | Placement | Eligibility |
| --- | --- | --- |
| Adaptive banner | Level selector and standard puzzle | Configured AdMob unit, UMP permission, adequate height, and no Remove Ads or Premium |
| Interstitial | Exit after completing a Level or Daily Challenge | Five qualifying exits, at least three minutes between impressions, one minute after a rewarded ad, and no active puzzle |
| Rewarded hint | Hint shop | One hint per earned callback, up to five per local day |
| Rewarded coins | Store · Earn Coins | Twenty coins per video, six per day, plus forty on the fourth |
| Rewarded boost | Boosts | Three 10-minute 2× Boosts per day; one separate 3× offer after four coin videos |
| Rewarded supply crate | Falling crate dialog | One successful viewing for the displayed amount |
| Rewarded Fortune Wheel | Fortune Wheel | Six video spins per rolling 24 hours, plus the separate free spin |

The Android build template specifies production IDs for five distinct units. Serving is disabled by default. Debug/profile test mode uses Google sample IDs, and the Android release consent-only mode can exercise UMP with production metadata while blocking all ad requests. See [publisher setup](../setup.md#4-before-enabling-advertisements).

Every rewarded placement is server-verified. The app asks the backend for a reward session, attaches its ID to the ad as SSV custom data, and the backend grants the reward only after Google's signed callback and a claim within the server's daily limits. Dismissal, no-fill and SDK errors pay nothing, and gameplay never depends on an ad loading. Optional rewards remain available to ad-free purchasers. Automatic interstitials appear only on exit from a completed puzzle, never during a drag. Remove Ads and Premium come from the server's entitlements, not from local flags.

The Store uses localized Google Play quotes. Themes owns palette browsing and unlocks, while Wallet owns the balance and transaction history. Each purchase carries the player's obfuscated billing account. The backend verifies it with the Play Developer API, credits it atomically, then consumes or acknowledges it. Balances and permanent entitlements are stored server-side and restore on any device signed into the profile. Premium applies both entitlements and a one-time 1,000-coin bonus per player. Refunds are reversed through RTDN and Voided Purchases reconciliation. iOS purchases are off until an App Store server verifier exists.
