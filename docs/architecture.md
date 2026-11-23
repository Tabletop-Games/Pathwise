# Architecture

The Flutter app uses Provider over an application state model. `Puzzle` defines the wall-free orthogonal grid. `GameController` owns route edits, stroke grouping, completion and hint highlighting. `puzzle_solver.dart` independently certifies uniqueness. Generation runs in an isolate. Views delegate progression and accounting to `AppModel`. Path drawing repaints the board without rebuilding the progression screens for each pointer update.

`AppModel` coordinates standard, daily, Expedition and Time Attack play. Daily uses local calendar dates. Time Attack uses Android elapsed realtime and boot identity, which includes time in the background. A different boot expires a resumed run.

The app saves schema 5 in the existing `pathwise.save.v1` SharedPreferences DataStore entry. A queued snapshot writer persists route, results, ledger, unlocks, timer state, boosts, expedition runs and hint state together. Ledger IDs deduplicate repeat fulfillment. Legacy experiments can retain ordinary progress but pre-release extra-hint credits are excluded. The app uses local snapshots for offline play and has no cross-device progression merge. Measure write amplification on long saves before introducing a database.

`BoardPalette` supplies app and board roles. The Vault lets players preview a palette without buying or equipping it. The 21 themes share system controls, gameplay feedback and progress layouts.
