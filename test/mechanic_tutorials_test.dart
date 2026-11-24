import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/mechanic_tutorials.dart';
import '../lib/logic/puzzle.dart';

void main() {
  test('mechanics are discovered from board content in stable order', () {
    final puzzle = Puzzle(
      3,
      [0, 8],
      walls: [(0, 1)],
      iceTiles: [1],
      gate: (2, 3),
      portal: (4, 5),
      arrow: (6, 7),
    );
    expect(mechanicsOnBoard(puzzle), MechanicTutorial.values);
    expect(unseenMechanics(puzzle, {'ice', 'gate'}), [
      MechanicTutorial.walls,
      MechanicTutorial.portal,
      MechanicTutorial.arrow,
    ]);
  });

  test('classic boards and unknown saved identifiers are safe', () {
    final puzzle = Puzzle(3, [0, 8]);
    expect(mechanicsOnBoard(puzzle), isEmpty);
    expect(unseenMechanics(puzzle, {'future-mechanic'}), isEmpty);
  });
}
