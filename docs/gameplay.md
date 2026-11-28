# Gameplay

This is the canonical description of how Pathwise plays. Economy numbers are in [economy.md](economy.md). If the code and this file disagree, fix whichever is wrong in the same change.

## Rules

- The only legal edges join two orthogonally adjacent cells. Every grid cell is playable.
- The route starts at checkpoint 1, visits each cell exactly once, visits consecutive checkpoints in order, and ends at the highest checkpoint.
- The highest checkpoint opens only when it is the last cell left. A locally legal route can still strand cells; the player backtracks to recover.
- Start or resume a stroke at the route tip. Drag backwards along the route to retract one step at a time, press an earlier route cell to truncate there, or tap a legal neighbour.
- Movement is cardinal. The cosmetic tip follows the finger along one axis and never moves diagonally ([tip tracker](../lib/logic/tip_tracker.dart)).
- **Undo** reverts the last completed input action, including a retraction. **Clear** returns the route to checkpoint 1 and can itself be undone. Neither stops the attempt clock.
- **Hint** follows the unique verified solution. It keeps the correct prefix, retracts a divergent tail, and highlights a progressively longer correct segment. Repeating Hint while a highlight is visible reuses it. The final move is always the player's.
- Completion needs full coverage and the final checkpoint in the same accepted move. The result, rewards and any advancement are saved in one snapshot.
- Puzzles are generated on the device. The generator builds a full route, derives checkpoints, and a bounded exhaustive solver must prove the solution is unique. A search timeout does not count as proof.

## Mechanics

Mechanics are introduced one at a time, practised, then combined. Entering a mechanic's first board opens a short practice tutorial on an isolated board; it never grants campaign rewards or advances progression, and it can be skipped, interrupted, and replayed from Settings → Demo.

| Mechanic | Rule |
| --- | --- |
| Walls | A wall blocks the connection between two adjacent cells. |
| Ice | Entering an ice tile slides the path straight on until it reaches a normal tile. |
| Keys and gates | The gate cell cannot be entered until the key cell has been visited. |
| Portals | Entering the source portal continues from its paired exit. |

The generator keeps mechanic tiles apart from checkpoints and rejects boards where a forced move would be blocked. The solver, the gesture controller, restore and hint routing share one set of movement rules in `lib/logic/puzzle.dart`.

## Modes

| Mode | Description |
| --- | --- |
| **Campaign** | An endless procedural campaign. Level seeds derive from `pathwise-catalogue-v3` and the level number. Boards are 4×4 for levels 1–30, 5×5 for 31–100, 6×6 for 101–300 and 7×7 from 301. Walls first appear at level 31, ice at 71, gates at 121 and portals at 201; walls and ice combine from 101; from 301 the combinations cycle. |
| **Daily Challenge** | Three deterministic boards (4×4, 5×5, 6×6) for the device's local calendar day. |
| **Time Attack** | Solve as many boards as possible in 1, 3 or 5 minutes, growing from 4×4 to 7×7 with a stable seed per run. Deadlines use Android elapsed time and boot identity, so changing the wall clock does not extend a run. Stop and Restart discard the active run. Best scores are kept per duration. |

Daily Challenge and Time Attack use classic movement; advanced mechanics appear in the campaign.

## Time and stars

- The attempt clock starts when the playable board is displayed. It does not wait for the first move and does not run while a mechanic tutorial is open or while the app is in the background. It stops at completion.
- Every campaign board has deterministic, replay-stable star thresholds derived from its difficulty (`lib/logic/star_rating.dart`). `StarThresholds.rate` returns 3, 2, 1 or 0 stars. The baseline three-, two- and one-star times (10, 20 and 30 seconds) are scaled by a bounded multiplier from 1.0× to 4.0× that depends on board size and a difficulty score.
- The gameplay star bar starts full and shrinks with elapsed time. The three stars sit on the bar, and each star loses its earnable appearance when its threshold passes. There are no threshold labels. The completion card shows the stars earned, the time and the next action.
- A replay can improve the saved best time and stars. It does not repeat first-clear rewards.

## Journey and rewards

- Journey shows the campaign bottom to top as a lazy path of isometric platforms. It opens at the current level, supports jumping to a level or chapter, and opens a replay from any completed platform. Chapters are 25 levels.
- **Chapter treasure.** Clearing all 25 levels of a chapter makes its treasure claimable. Claiming is local and ad-free and grants 25 coins and one hint exactly once (one ledger entry and the hint in the same save).
- **Completion multiplier.** After a first campaign clear, the player may stop a moving 2×/3×/4× marker (3× only when reduced motion is on). A rewarded video then grants the difference on the clear's earned coins, once per level, only after the SDK earned callback. Nothing about the clear depends on ads or the network.
- **Mystery reward.** Every tenth first campaign clear produces a mystery reward (coins, a boost, a tip or a theme) chosen deterministically from what the player does not already own. It is revealed on the results screen, claimed with a rewarded video, and can be skipped, which discards it. A claim is applied once. Items the player acquires in the meantime are replaced by a deterministic alternative.

## Daily streak

A qualifying clear (a campaign or Daily puzzle, or at least two Time Attack solves) extends the daily streak. Streak Freezes (maximum two) preserve continuity over a missed day without increasing the count. Milestone and weekly coin rewards are listed in [economy.md](economy.md).

## Hints

New profiles start with three hints. The wallet is global across modes and survives new puzzles, Replay, Clear and Time Attack restarts. Hints are bought with coins or earned from a rewarded video. Per-attempt usage is kept for statistics.

## Notifications

Optional local notifications (off by default, permission requested on opt-in): a Daily Challenge reminder, a streak reminder and an invitation reminder. Timing adapts to when the player usually plays, within quiet hours (22:00–08:00 by default). Notifications are scheduled on the device and need no network.

## Sharing

Text-only results can be shared for Daily Challenge, Time Attack, campaign milestones, achievements and research milestones, through the Android share sheet. Sharing is a suggestion that can be turned off in Settings. See [social-sharing.md](social-sharing.md).
