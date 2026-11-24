# Architecture

The Flutter app uses Provider over an application state model. `Puzzle` defines the grid and enabled movement rules. `GameController` owns route edits, stroke grouping, completion and hint highlighting. `puzzle_solver.dart` independently certifies uniqueness. Generation runs in an isolate. Views delegate progression and accounting to `AppModel`. Path drawing repaints the board without rebuilding the progression screens for each pointer update.

`AppModel` coordinates Levels, Daily Challenge and Time Attack play. Daily uses local calendar dates and saves gates between three boards. Time Attack uses native elapsed time and boot identity, which includes time in the background. A different boot expires a resumed run.

The app saves schema 12 in the existing `pathwise.save.v1` SharedPreferences DataStore entry. A queued snapshot writer persists route, results, ledger, unlocks, timer state, boosts, crate eligibility, hint state and native achievement progress together. Ledger IDs deduplicate repeat fulfillment. Legacy experiments can retain ordinary progress but pre-release extra-hint credits are excluded. The app uses local snapshots for offline play and has no cross-device progression merge. Measure write amplification on long saves before introducing a database.

`BoardPalette` supplies app and board roles. Themes lets players preview a palette without buying or equipping it. The Store owns localized purchases and rewarded coin offers; Wallet owns the balance and transaction history; Settings owns privacy and consent controls. The 23 themes share system controls, gameplay feedback and progress layouts.

The schema 9 migration keeps wallet balances, purchased themes, completed levels, Daily and Time Attack history, the historical hint tank, and lifetime counters from removed modes. Retired Research and unused boost purchases are refunded once from recorded ledger prices. Historical reward credits remain part of the balance. Obsolete run data is ignored.

Schema 11 moves hints into a single wallet, keeps existing coin transactions and entitlements, and records new streak data and placement quotas. Debug builds use a separate preference key.

Advanced Levels add walls and value-bearing tile rules. The solver uses the same movement predicate as gesture handling. Restored older attempts retain their original board seeds and rules.
