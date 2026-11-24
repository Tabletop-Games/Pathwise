# Design: game-first UI/UX overhaul

## Design system (`lib/ui`)
- `game_ui.dart`: `GameTokens` (spacing 4/8/12/16/24, radii 12/16/22/999, durations), `GameColors` extension on `BoardPalette` (card, cardRaised, outline, accentPill, quietPill, selectedSegment, success), and widgets `GameCard`, `PricePill`, `ActionPill`, `GameSegmented`, `GameScreen`, `SectionLabel`, `ProgressPips`, `RewardAmount`, `GameDialog`, `showGameDialog`, `CompactTile`.
- `game_art.dart`: original `CustomPainter` art: coin, coin stacks (five sizes), gift, chest/crate, store bag, lock, no-ads shield, theme brush, crown, bolt, research glyphs, achievement emblem, flame.
- Colours always come from `BoardPalette` plus derived shades (`Color.lerp`, HSL lightness shifts). No fixed grey/white/black/orange.

## Tip artwork (`lib/views/components/tip_art.dart`)
Each tip is a layered Bézier illustration drawn upright (forward = up) in a ±1 box. `paintPathTip(..., quarterTurns)` keeps the existing meaning (0 right, 1 down, 2 left, 3 up), so gameplay rotates the art and the catalogue shows it upright (`TipArtwork` defaults to up). Colours: an identity palette per tip is tinted toward the theme accent, lightness-clamped, and given a dark contrast outline derived from the fill, so every character stays recognisable under every theme.

## Pointer tracking (`lib/logic/tip_tracker.dart`, `puzzle_board.dart`)
`TipTracker` is pure Dart. Inputs: puzzle, accepted route, pointer in board units, a legality callback. State: facing, extreme coordinate along facing (hysteresis), rebase flag. Output `TipVisual{position, facing, extension}`.
- Axis through the last accepted cell centre. Extension `e = dot(P - C, f)` clamped to `[-0.5, max]`; negative values exist only while the finger is still in the cell just left and a previous route cell is behind the tip.
- `max` is 0.5 for a legal neighbour (the validator accepts at the cell boundary and tracking continues from the new centre, so there is no jump), and `0.5 - tipRadius - 0.02` for any blocked neighbour (wall, gate, wrong checkpoint, visited, board edge).
- Facing flips when the finger retreats more than 0.14 cells from its furthest point on the current facing, or when the perpendicular offset exceeds the along offset by 25 % plus a 0.1 dead zone. Facing is always one of four cardinals.
- Ice slides, portal transport and multi-cell retractions set a rebase flag: the tip rests on the accepted cell with the accepted facing until the finger reaches that cell.
- Release or cancel clears the visual and settles over 90 ms (immediately with reduced motion).
`PuzzleBoard` keeps the board layer static, adds one light tip layer driven by `ValueNotifier<TipVisual?>`, and leaves the rejection layer for the temporary segment. The tip layer draws the resting tip too, so the board layer no longer paints it.

## Checkpoint composition
On a checkpoint the tip keeps radius 0.21 and sits 0.30 cells ahead of the checkpoint centre, overlapping the disc's leading rim. The number shifts back 0.08 and shrinks 20 % for two digits so it stays clear. Classic keeps its accent-disc treatment.

## Screens
Main menu, Store (four categories), Levels, Daily/Time Attack, gameplay, completion, Wheel, Research, Boosts, Streak, Statistics and Achievements, dialogs, Settings, tutorials, crates, connection and cloud save are redesigned with the shared components. See `audit.md` for the inventory and per-screen status.

## Testing
Pure tests for the tracker. Widget tests for the board layers, Store, menu and dialogs. A capture suite renders each major screen under six themes and three viewports to PNG; CI uploads the images and they are inspected. Contrast checks cover tip colours and pills per theme.
