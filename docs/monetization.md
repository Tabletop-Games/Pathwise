# Monetization

Production capability flags default off. The publisher enters app and unit identifiers outside source control using [setup.md](../setup.md).

| Format | Placement | Eligibility |
| --- | --- | --- |
| Anchored adaptive banner | Level selector and puzzle scaffold, including Time Attack | Configured unit and UMP permission. Hidden for Remove Ads and Premium. |
| Interstitial | Exit following a completed Level or Daily puzzle | Five qualifying exits, at least four minutes between impressions, one minute after rewarded ads, current route resumed and no active puzzle. Hidden for Remove Ads and Premium. |
| Rewarded refill | Refill Hints | Tank below capacity. Restores exactly 3/3. |
| Rewarded extra hint | Extra Hint dialog | Three standard hints already spent. One further hint. |
| Rewarded coins | Vault | Eight coins, up to three per local day. |
| Rewarded Fortune Wheel | Fortune Wheel | Up to four per rolling 24 hours. Signed SSV and server-enforced selection and limit. |

Reward actions each have their own configured unit. Production needs both SDK reward completion and a signed AdMob SSV receipt for the corresponding nonce. Dismissal alone yields no reward. Optional ads stay visible to ad-free purchasers when available.

The Vault uses Google Play localized quotes, verification before local fulfillment, consumable consumption, permanent purchase acknowledgement and restore. Premium grants both entitlements and a stable one-time 1,000-coin event. See [backend](backend.md) for recovery boundaries.

## Social sharing and Play Games

Both features work independently of Billing, AdMob, Premium and the hint tank. Share actions confer no virtual rewards. Native achievement confirmation confers no wallet credit. [Social sharing](social-sharing.md) [Google Play achievements](google-play-achievements.md)
