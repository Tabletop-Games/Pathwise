# Gameplay research and Pathwise specification

## Reference evidence

- [Live Zip game](https://www.linkedin.com/games/zip) presents a start screen. The linked board endpoint encountered a sign-in screen in this environment.
- [LinkedIn Help](https://www.linkedin.com/help/linkedin/answer/a7445030) verifies the ordered checkpoints, complete coverage, drag from 1, tap or drag to retract, Undo for the last move, Hint back to the first error with one correct step revealed, Reset (also called Clear in an earlier revision), mobile haptics, and the results screen.
- [Official showcase](https://www.linkedin.com/showcase/zip-game/) describes the objective and publishes daily solve-throughs.
- [Official launch solve-through](https://www.linkedin.com/posts/zip-game_zip-no-1-activity-7307749273050259458-r3LI), inspected from the actual video. Around 34–46 seconds, a wall-free board draws the route as a continuous stroke through cell centers, with rounded turns, an immediate visited-cell tint and numerals visible above the stroke. Around 45–47 seconds the pointer moves back over the route and the tail shrinks as it moves.
- [Official Zip No. 116 solve-through](https://www.linkedin.com/posts/zip-game_zip-no-116-activity-7349331654580105216-oC4Q), inspected from the actual video. Around 10–22 seconds the route renders while the pointer moves. Undo is disabled during the early uninterrupted stroke and available after a completed input group. Around 60–65 seconds the filled board reaches the final checkpoint and transitions to a completion overlay. This board includes dividers, which are outside the Pathwise rules.
- [LinkedIn launch announcement](https://news.linkedin.com/2025/linkedin-announces-zip-) describes the daily timed path puzzle. Neither inspected solve-through demonstrates a Hint button press. Help establishes its correction and reveal behavior, but the precise animation and whether its suggested step is drawn into the active path could not be verified.

## Pathwise rules

- The only legal edges join two orthogonally adjacent cells. Every grid cell is playable, with no dividers or blocked edges.
- The route starts at checkpoint 1, visits each cell once, visits consecutive checkpoints in order and finishes at the highest checkpoint.
- The highest checkpoint opens only when it is the last cell left. A locally legal route can still strand cells, and the player can backtrack to recover.
- Start or resume a stroke at the route tip. Drag along the route in reverse to retract one step at a time. Press an earlier route cell to truncate there. A tap on a legal neighbor also works.
- A finished drag or tap is one Undo action. Undo restores the route as it stood before that action, including any retracted section. Clear empties the route back to checkpoint 1 and keeps the attempt clock running. Clear itself can be undone.
- Hint uses the unique verified solution. It preserves the correct prefix, retracts any divergent tail, and highlights a progressively longer segment. Repeated presses while the same highlight is visible reuse the hint. The [hint tank](hints.md) controls authorization. Undo can recover an automatically retracted tail. The highlight is a Pathwise design choice based on the documented reveal behavior.
- Completion requires coverage and correct final checkpoint in the same accepted move. The timer counts active play from the first move or hint, pauses off the board or in the background, and freezes at completion. Pathwise shows a distinct completion animation and submits the route, time and hint usage to the server, which validates them against the regenerated board.
- Puzzles are original. The generator finds a full route, derives checkpoints and passes them to an independent bounded exhaustive solver. Only a completed uniqueness proof is accepted. A search timeout does not establish uniqueness.
- Daily puzzles use a deterministic seed for the device's local calendar day. All modes need an online session. Gameplay itself runs on the device, and connectivity loss pauses the board without losing the route. See [game modes](game-modes.md) and [online architecture](online-architecture.md).


## Advanced Levels

The 1,000-level catalogue introduces walls at 31, ice at 71, gates at 121 and portals at 201. Levels 101–120 first combine walls and ice. From 301 onward combinations cycle through the learned mechanics. Entering the source portal automatically appends its destination; ice continues straight until reaching a regular tile. The generator keeps mechanic tiles separate from checkpoints and rejects blocked forced moves as a group. A bounded solver certifies uniqueness. See [catalogue evaluation](catalogue.md) for the measured distribution and limitations.
