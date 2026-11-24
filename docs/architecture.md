# Architecture

The Flutter app uses Provider over an application state model and is online-first. `OnlineService` owns identity, sessions and reachability, and the backend is authoritative for the economy and progression. See [online architecture](online-architecture.md). `Puzzle` defines the grid and enabled movement rules. `GameController` owns route edits, stroke grouping, completion and hint highlighting. `puzzle_solver.dart` independently certifies uniqueness. Generation runs in an isolate. Views delegate progression and accounting to `AppModel`. Path drawing repaints the board without rebuilding the progression screens for each pointer update.

`AppModel` coordinates Levels, Daily Challenge and Time Attack play. Daily uses local calendar dates and saves gates between three boards. Time Attack runs are created and timed by the server, and the device's boot-relative clock only drives the on-screen countdown. Disconnecting or backgrounding does not extend a run.

The app keeps schema 13 in the `pathwise.save.v1` SharedPreferences entry as a **cache** of the last server state plus the active route. A queued snapshot writer persists it so the route survives a restart while offline. The server's state replaces it on every connection. The identity and the pending-command outbox are stored separately (`pathwise.identity.v1`, `pathwise.outbox.v1`). Debug builds use `.debug` keys. Older development saves are not migrated into the server.

`BoardPalette` supplies app and board roles. Themes lets players preview a palette without buying or equipping it. The Store owns localized purchases and rewarded coin offers; Wallet owns the balance and transaction history; Settings owns privacy and consent controls. The 23 themes share system controls, gameplay feedback and progress layouts.

Historical note: the schema 9 migration kept wallet balances, purchased themes, completed levels, Daily and Time Attack history, the historical hint tank, and lifetime counters from removed modes. Retired Research and unused boost purchases are refunded once from recorded ledger prices. Historical reward credits remain part of the balance. Obsolete run data is ignored.

Schema 11 moved hints into a single wallet, keeps existing coin transactions and entitlements, and records new streak data and placement quotas. Debug builds use a separate preference key.

Advanced Levels add walls and value-bearing tile rules. The solver uses the same movement predicate as gesture handling. Restored older attempts retain their original board seeds and rules.
