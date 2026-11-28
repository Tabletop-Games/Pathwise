import 'puzzle.dart';

/// Stable identifiers for tutorial completion records, independent of levels.
enum MechanicTutorial {
  walls('walls'),
  ice('ice'),
  gate('gate'),
  portal('portal');

  const MechanicTutorial(this.id);
  final String id;
}

/// Discovers mechanics from the actual board.
/// Order is stable so boards introducing multiple mechanics have a predictable
/// tutorial sequence. This function does not mutate the puzzle or player state.
List<MechanicTutorial> mechanicsOnBoard(Puzzle puzzle) => [
  if (puzzle.walls.isNotEmpty) MechanicTutorial.walls,
  if (puzzle.iceTiles.isNotEmpty) MechanicTutorial.ice,
  if (puzzle.gate != null) MechanicTutorial.gate,
  if (puzzle.portal != null) MechanicTutorial.portal,
];

/// Completed and explicitly skipped tutorials are both excluded; an opened
/// tutorial is not recorded until the caller persists an explicit outcome.
List<MechanicTutorial> unseenMechanics(Puzzle puzzle, Set<String> dismissed) =>
    mechanicsOnBoard(puzzle)
        .where((mechanic) => !dismissed.contains(mechanic.id))
        .toList(growable: false);
