# Quiet Journey

The campaign leads Home, with a line-drawn landscape, chapter title and a single Play action. Daily Challenge follows as a quiet recurring ritual. Chapters group 25 existing puzzles, with direct replay and level selection preserved. A chapter celebration requires all 25 solves and adds no currency. The composition board and implementation notes are in [.kiro/specs/quiet-journey](../.kiro/specs/quiet-journey).

The design takes cues from word puzzles' campaign rhythm and short reward reveals, and from minimalist route and colour puzzles' strong focal points and quiet backgrounds. Pathwise's artwork is drawn in code and derives its colours from the equipped palette. The previous set of twenty original tip vectors remains in use.

Every prospective first campaign clear adds one tenth of a discovery. Ten clears reserve the first eligible unowned, unreserved catalogue item. Keep pending finds indefinitely. If the item is already owned or the catalogue is exhausted, the earned callback grants 20 coins instead. Theme entitlements count as ownership. Apply is explicit. Normal progress is independent of ads.

The 2×/3×/4× video reward only multiplies the configured campaign base, and grants the difference after the earned callback. The fixed 3× option is available without timing. Each paid bonus has one ledger identity per level. Stopped offers live on the current completion screen. An interrupted, unearned multiplier is abandoned on leaving or restarting. Discovery offers remain in Collections. The previous automatic free-coin prompt was retired. Voluntary Store videos remain available. No new daily cap is imposed on the completion reward; ad readiness, consent, foreground and existing spacing still apply.

Local saves move to schema 14 and cloud envelopes to version 3. Older saves keep their existing balances, ownership and progress; the new journey counts only new clears. The existing Play Games conflict picker selects one coherent economy, so restoring an older snapshot replaces the balance and reward state together. Independent devices can watch ads against different snapshots and the client cannot authenticate ad history across devices or prevent tampering. The two rewards use the existing AdMob SDK and need no additional placements or services.

Run `dart run tool/journey_economy.dart` for the incremental economy estimate. It isolates campaign rewards, uses the actual track widths (mean extra reward 7.30 coins per video at the current base), and assumes every tenth completion prioritizes discovery. Other economy flows, superseded free-coin prompts, and fill rates are excluded; ad-watch fractions are scenario assumptions.

| Scenario | Previous coins/day | New coins/day | Cosmetic claims/day | Videos/day |
| --- | ---: | ---: | ---: | ---: |
| Casual, no ads | 15 | 15 | 0 | 0 |
| Casual, occasional ads | 15 | 19.4 | .06 | .6 |
| Regular | 50 | 71.9 | .30 | 3 |
| Dedicated | 125 | 188.8 | .88 | 8.8 |
| Active boost | 100 | 121.9 | .30 | 3 |
| Substantial research | 210 | 231.9 | .30 | 3 |
| Premium | 50 | 57.3 | .10 | 1 |
| Catalogue exhausted | 50 | 77.9 | 0 | 3 |

A 100-coin tip costs roughly two days of base campaign earnings in the regular scenario, or 1.4 days with these video assumptions. Themes, research and boosts become affordable at the same rate relative to their existing prices. The dedicated scenario adds roughly 51% to base campaign income, so review actual video usage before tuning bonuses. No prices or existing reward rates were changed.
