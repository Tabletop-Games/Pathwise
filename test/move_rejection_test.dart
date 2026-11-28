import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/game_controller.dart';
import '../lib/logic/puzzle.dart';

void main() {
  test('rule reasons preserve existing validation decisions', () {
    final wall = Puzzle(3, [0, 2, 8], walls: [(0, 1)]);
    expect(wall.rejectionFor(0, 1, 1, 2), MoveRejection.wall);
    expect(wall.canExtend(0, 1, 1, 2), isFalse);
    final gate = Puzzle(3, [0, 8], gate: (3, 1));
    expect(gate.rejectionFor(0, 1, 1, 2), MoveRejection.gate);
    expect(gate.rejectionFor(0, 1, 1, 2, hasVisited: (c) => c == 3), isNull);
    final checkpoint = Puzzle(3, [0, 2, 1, 8]);
    expect(checkpoint.rejectionFor(0, 1, 1, 2), MoveRejection.checkpoint);
  });

  test('rejection inspection never changes route or undo history', () {
    final puzzle = Puzzle(3, [0, 2, 1, 8]);
    final game = GameController(
      VerifiedPuzzle(puzzle, [0, 3, 6, 7, 4, 5, 2, 1, 8]),
    );
    expect(game.begin(0), isTrue);
    final before = game.path;
    expect(game.rejectionFor(1)?.reason, MoveRejection.checkpoint);
    expect(game.path, before);
    expect(game.history, isEmpty);
    expect(game.nextCheckpoint, 2);
  });

  test(
    'mechanic restrictions and forced failures identify the obstruction',
    () {
      final ice = Puzzle(3, [0, 8], iceTiles: [1]);
      expect(ice.rejectionFor(1, 4, 2, 2, previous: 0), MoveRejection.ice);
      final portal = Puzzle(3, [0, 8], portal: (3, 1));
      expect(portal.rejectionFor(0, 1, 1, 2), MoveRejection.portal);
      expect(portal.rejectionFor(0, 5, 1, 2), MoveRejection.adjacency);

      final blockedIce = Puzzle(3, [0, 8], iceTiles: [1], walls: [(1, 2)]);
      final game = GameController(
        VerifiedPuzzle(blockedIce, [0, 3, 4, 1, 2, 5, 8, 7, 6]),
      );
      game.begin(0);
      final rejection = game.rejectionFor(1)!;
      expect(rejection.reason, MoveRejection.wall);
      expect((rejection.from, rejection.target), (1, 2));
      expect(game.step(1), RouteEdit.none);
      expect(game.path, [0]);

      final blockedPortal = Puzzle(3, [0, 8], portal: (1, 0));
      final portalGame = GameController(VerifiedPuzzle(blockedPortal, [0, 1]));
      portalGame.begin(0);
      expect(portalGame.rejectionFor(1)?.reason, MoveRejection.portal);
      expect(portalGame.step(1), RouteEdit.none);
      expect(portalGame.path, [0]);
    },
  );

  test('revisits reject but normal backtracking stays legal', () {
    final puzzle = Puzzle(3, [0, 8]);
    final game = GameController(
      VerifiedPuzzle(puzzle, [0, 1, 2, 5, 4, 3, 6, 7, 8]),
    );
    game.begin(0);
    game.step(1);
    game.step(4);
    expect(game.rejectionFor(1), isNull);
    expect(game.step(1), RouteEdit.retract);
    expect(game.rejectionFor(0), isNull);
    game.step(4);
    expect(game.rejectionFor(0)?.reason, MoveRejection.revisit);
    expect(game.path, [0, 1, 4]);
  });
}
