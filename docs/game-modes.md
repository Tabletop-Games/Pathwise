# Game modes

## Decision

Endless offered another unlimited sequence with recurring board sizes and no run objective. Levels already fills that role. Time Attack already rewards solving quickly against a fixed clock.

Each rating is out of ten. The total is the weighted mean. A higher maintenance score means a smaller maintenance burden.

| Candidate | Distinctiveness 25% | Replay 20% | Enjoyment 20% | Mechanics 15% | Economy 10% | Maintenance 10% | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Expedition | 9 | 9 | 9 | 9 | 9 | 8 | 8.90 |
| Survival | 8 | 8 | 7 | 7 | 8 | 8 | 7.65 |
| Puzzle Rush | 5 | 8 | 8 | 9 | 7 | 8 | 7.30 |
| Gauntlet | 8 | 7 | 8 | 9 | 8 | 9 | 8.05 |
| Discovery | 9 | 9 | 8 | 8 | 8 | 5 | 8.15 |
| Relay (linked board objectives) | 9 | 7 | 7 | 8 | 7 | 6 | 7.55 |

Expedition wins because a route has a finish, voluntary stage objectives, a qualification target and a reason to replay for a better record. Survival risks penalizing experimentation. Puzzle Rush repeats the pressure of Time Attack. A curated Gauntlet has a strong finish with less variation between runs. Discovery requires more navigation and authored content. Relay would entangle otherwise independent puzzles.

## Rules

Three trails, ten stages each. Solve all ten stages and earn at least two of four optional field marks to clear a trail and unlock the next. Stages 2 and 7 award marks for solving without hints. Stages 4 and 9 award marks for solving without Clear. Retraction and Undo are allowed. Missing a mark keeps the stage and run playable. Finishing without two marks records an unsuccessful run. Choosing End run records an abandonment. Leaving the screen or closing the app preserves the run and current stage.

The trail map exposes conditions before play. Personal records store the deepest run, most marks and fastest qualifying clear per trail. Wall-clock time away from the board does not count.

## Economy and integrity

Stages 3 and 6 pay 12 coins each on their first clear per trail. The first qualifying completion of each trail pays 36. Milestone IDs are tied to the trail, so abandoning, replaying or restarting cannot repeat them. A first trail clear awards a local achievement through the existing achievement ledger and Research bonus. Qualifying on Summit earns Basin Gold, a cosmetic also available with the all-themes entitlement. Ordinary crates remain available under their existing global daily cap. Adaptive banners follow the existing consent rules. Expedition transitions do not trigger automatic interstitials. Coin boosts do not multiply trail awards.

The shared three-slot tank follows the same rules as other modes. Assistance forfeits only a hint-free mark and any fourth or later hint still requires its own verified ad. No leaderboard is offered. Records are local, with fastest qualifying clears measured using active board time.

## Implementation and checks

Expedition uses versioned deterministic trail, run variant and stage seeds, rising board sizes and decreasing checkpoint density within board bands. The existing solver certifies every accepted layout. A budgeted solver fallback can retain more checkpoints for uniqueness. The ordinary controller, renderer and saved route snapshots are shared with the other modes.

All 360 published boards were generated and checked for a unique solution during release verification. Across all twelve variants per trail, the average longest stretch between checkpoints grows from 3.2 to 5.8 moves on Foothills, 4.3 to 7.8 on Ridgeline, and 6.3 to 12.5 on Summit.

Each trail has twelve seed variants. Run identity stays unique even after a variant repeats. Schema 5 keeps the active stage and its route, durable per-trail records and the latest twelve summaries. Earlier completed Endless puzzles remain in aggregate statistics. Unfinished Endless routes and obsolete hint credits are cleared during upgrade, while the shared tank and credits from other modes are preserved.

The automated suite verifies run qualification and failure, trail unlocks, abandoned and resumed runs, process-recreation snapshots, deterministic solver-certified generation, hint isolation, first-only rewards, cosmetic ownership, and navigation through the shared drag interface. No network service is needed to start or finish a trail.
