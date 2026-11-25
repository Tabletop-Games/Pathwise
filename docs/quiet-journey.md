# Quiet Journey

The campaign leads Home, with a line-drawn landscape, chapter title and a single Play action. Daily Challenge follows as a quiet recurring ritual. Chapters group 25 existing puzzles, with direct replay and level selection preserved. A chapter treasure requires all 25 solves and grants 25 coins and one hint when claimed. The composition board and implementation notes are in [.kiro/specs/quiet-journey](../.kiro/specs/quiet-journey).

The design takes cues from word puzzles' campaign rhythm and short reward reveals, and from minimalist route and colour puzzles' strong focal points and quiet backgrounds. Pathwise's artwork is drawn in code and derives its colours from the equipped palette. Catalogue portraits share their colours and identifying marks with directional gameplay silhouettes.

Every prospective first campaign clear adds one tenth of a discovery. Ten clears reserve the first eligible unowned, unreserved catalogue item. Keep pending finds indefinitely. If the item is already owned or the catalogue is exhausted, the earned callback grants 20 coins instead. Each subsequent ten-clear milestone can reserve a coin fallback while no fallback is pending. Theme entitlements count as ownership. Apply is explicit. Normal progress is independent of ads.

The 2×/3×/4× video reward only multiplies the configured campaign base, and grants the difference after the earned callback. The pointer moves as soon as results appear, even if the player is offline. Reduced motion uses a fixed 3× offer. Each paid bonus has one ledger identity per level. Stopped offers live on the current completion screen. An interrupted, unearned multiplier is abandoned on leaving or restarting. Discovery offers remain in Collections. The previous automatic free-coin prompt was retired. Voluntary Store videos remain available. No new daily cap is imposed on the completion reward; ad readiness, consent, foreground and existing spacing still apply.

Local saves move to schema 15 and cloud envelopes to version 4. Older saves keep their existing balances, ownership and progress; the new journey counts only new clears. The existing Play Games conflict picker selects one coherent economy, so restoring an older snapshot replaces the balance and reward state together. Independent devices can watch ads against different snapshots and the client cannot authenticate ad history across devices or prevent tampering. The two rewards use the existing AdMob SDK and need no additional placements or services.

Run `dart run tool/journey_economy.dart` for the incremental economy estimate. It isolates campaign rewards, uses the actual track widths (mean extra reward 7.30 coins per video at the current base), and assumes every tenth completion prioritizes discovery. Other economy flows, superseded free-coin prompts, and fill rates are excluded; ad-watch fractions are scenario assumptions.

## Endless campaign

The journey uses a reversed, fixed-extent lazy list. A level maps directly to its scroll slot, with one chest inserted after every 25 levels. The journey starts at the current level, increases upwards and supports direct jumps. The paged grid remains available for quick navigation. The chapter art uses eight environments with deterministic variations. Seeds and best-time records retain their previous identities.

Chapter chests are prospective. A chapter that was already fully complete before migration attracts no new reward. Complete the last outstanding puzzle of an unfinished chapter to earn its chest. Pending chests stay visible in the journey and their own list on Home. A claim is local and ad-free. The coin ledger records the chapter ID, and the same save records the hint and removes the pending marker. Cloud reconciliation preserves this state as one economy unit.

## Economy estimate

A completed 25-level chapter now adds 25 coins and one hint. In the long run that is one coin and 0.04 hints per puzzle if every chest is claimed. That adds 20% to the five-coin base for players who use no ads, with no scaling by chapter number or replay credits. Chapter chests carry no separate video offer. The following estimates compare against Quiet Journey, keeping its assumed ad take-up unchanged.

| Scenario | Previous coins/day | With chests | Chest hints/day |
| --- | ---: | ---: | ---: |
| Casual, no ads | 15.0 | 18.0 | 0.12 |
| Casual, occasional ads | 19.4 | 22.4 | 0.12 |
| Regular | 71.9 | 81.9 | 0.40 |
| Dedicated | 188.8 | 213.8 | 1.00 |
| Active boost | 121.9 | 131.9 | 0.40 |
| Substantial research | 231.9 | 241.9 | 0.40 |
| Premium | 57.3 | 67.3 | 0.40 |
| Catalogue exhausted | 77.9 | 87.9 | 0.40 |

Actual ad availability and timing selections can change video income. The fallback estimate assumes regular claims. Existing prices and payouts remain in place.
