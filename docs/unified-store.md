# Store and path tips

The Store contains Themes, Tips, Coins and Upgrades. The header and category selector stay in place while each catalogue scrolls. Theme previews use the actual Level 1 puzzle and a shared partial solution; opening a preview does not equip or purchase it. Purchased themes retain their existing prices and entitlement rules.

Classic is the default tip. Each of the 19 additional original vector tips currently costs 100 coins; each price is configured independently in `EconomyRules`' `PathTip` catalogue. Previewing does not purchase or equip. Buying adds one stable `tip/<id>` ledger debit and ownership to a single saved snapshot; Apply changes the equipped tip separately. Artwork uses board palette roles and faces the most recent accepted cardinal movement, excluding portal transport.

The Play Games cloud envelope version 2 includes tip ownership and selection in the economy conflict unit. Version 1 envelopes are checksum-validated before migration to Classic. The existing cloud conflict picker remains responsible for choosing between divergent economies; tips are not silently merged across competing purchases. No hosted service is required.

Optional automatic coin-video offers use the same reward amount, ad service and daily limits as voluntary videos. Offers are checked after leaving a completed level, require five newly completed levels and a 15-minute gap, and are suppressed when ads are unavailable or the player owns Remove Ads or Premium. Only the earned-reward callback grants coins.
