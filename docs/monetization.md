# Monetization

Live ads and billing are off by default. Enable them only after the checklist in [play-console-setup.md](play-console-setup.md) is complete, using the Play internal track and AdMob test units first. Build flags are in [development.md](development.md#configuration). Reward values and limits are in [economy.md](economy.md#ads).

## Advertising

| Format | Placement |
| --- | --- |
| Adaptive banner | Standard puzzle screen, hidden for Remove Ads and Premium |
| Interstitial | After a completed campaign or Daily exit, spaced by the ad-frequency rules, never during play |
| Rewarded | Hint shop, Store coins, Boosts, falling crate, Fortune Wheel, campaign completion multiplier, mystery reward |

Gameplay never waits for an ad. Optional rewarded videos remain available to ad-free players. Rewards come only from the SDK's earned callback: dismissal, load failure or show failure pays nothing, and each reward instance pays once. Android debug and profile builds use Google's sample ad units. The release build can run consent (UMP) with production metadata while blocking ad requests.

Rewards are verified on the device, which is weaker than server-side verification; see [security.md](security.md).

## Purchases

The Store sells coin packs (consumable) and three permanent upgrades through Google Play Billing:

| Product | Effect |
| --- | --- |
| Coin packs | Coins, five sizes, localized Play prices |
| Remove Ads | Removes banners and automatic ads; optional rewarded videos remain |
| Themes Forever | Unlocks every current and future theme (not tips) |
| Premium | Remove Ads, Themes Forever and a one-time 1,000-coin bonus |

The app verifies the Play-signed purchase on the device against the configured licensing public key, checks package, product and token, saves the grant (keyed by a hash of the purchase token) and only then consumes or acknowledges it. Pending and cancelled purchases never grant. On start the app asks Google Play which permanent products the account owns and sets entitlements to match, so refunds and reinstalls are reconciled. Consumed coin packs cannot be rebuilt from Billing after save loss. If billing is unavailable the Store shows the packs with an unavailable price, never an invented one.

Product IDs are in `lib/model/product_catalog.dart`.
