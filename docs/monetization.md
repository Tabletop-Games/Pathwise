# Monetization

Production flags default off. See the publisher configuration and device test checklist. [Setup](../setup.md)

| Format | Placement | Eligibility |
| --- | --- | --- |
| Adaptive banner | Level selector and standard puzzle | Configured AdMob unit, UMP permission, adequate height, and no Remove Ads or Premium |
| Interstitial | Exit after completing a Level or Daily Challenge | Five qualifying exits, four minutes between impressions, one minute after a rewarded ad, and no active puzzle |
| Rewarded refill | Refill Hints | Restores remaining eligible standard hints |
| Rewarded extra hint | Extra Hint | A separate earned reward for each hint after the third |
| Rewarded coins | Vault | Eight coins, up to three per local day |
| Rewarded supply crate | Falling crate dialog | One successful viewing for the displayed amount |
| Rewarded Fortune Wheel | Fortune Wheel | Four video spins per rolling 24 hours, plus the separate free spin |

Client-side AdMob rewards require the SDK earned callback. Placement-specific handlers apply a unique transaction to the local save. Dismissal without earning has no payout. Optional rewards remain available to ad-free purchasers. Local payouts offer weaker tamper resistance than remotely verified receipts.

The Vault uses localized Google Play and App Store quotes. On Android, the app verifies the Play-signed purchase with the configured public key. On iOS, it confirms a matching verified StoreKit 2 transaction. Fulfillment is saved before consumption or acknowledgement. Premium applies both entitlements and a stable one-time 1,000-coin event per local profile. Consumable recovery after save loss and automatic refund reconciliation are unavailable.
