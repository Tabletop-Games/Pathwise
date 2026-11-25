import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/puzzle.dart';
import '../lib/logic/tip_tracker.dart';

// 4 x 4, cells numbered row by row. Cell 1 centre is (1.5, 0.5).
Puzzle open4({List<(int, int)> walls = const [], (int, int)? gate}) =>
    Puzzle(4, [0, 15], walls: walls, gate: gate);

TipVisual at(
  TipTracker tracker,
  Puzzle puzzle,
  List<int> route,
  Offset pointer, {
  int facing = 0,
  bool Function(int)? canEnter,
}) => tracker.update(
  puzzle: puzzle,
  route: route,
  pointer: pointer,
  acceptedFacing: facing,
  canEnter: canEnter ?? (cell) => !route.contains(cell),
);

void main() {
  late TipTracker tracker;
  setUp(() => tracker = TipTracker());

  test('rest prefers a legal unvisited direction and can stay neutral', () {
    final puzzle = open4(walls: [(0, 1)]);
    final visited = [0, 4, 5];
    expect(TipTracker.restingFacing(puzzle, [0], 3, (cell) => cell == 4), 1);
    expect(
      TipTracker.restingFacing(puzzle, visited, 3, (cell) => cell != 1),
      0,
    );
    expect(TipTracker.restingFacing(puzzle, visited, 1, (_) => true), 1);
    expect(
      TipTracker.restingFacing(puzzle, visited, 2, (cell) => cell == 4),
      -1,
    );
    final deadEnd = TipTracker.rest(puzzle, [0], -1);
    expect(deadEnd.tip, deadEnd.center);
    expect(deadEnd.extension, 0);
  });

  group('continuous tracking before a cell is accepted', () {
    test('horizontal: the tip follows the finger between cell centres', () {
      final puzzle = open4();
      final route = [0, 1];
      final a = at(tracker, puzzle, route, const Offset(1.5, .5));
      expect(a.tip, const Offset(1.5, .5));
      final b = at(tracker, puzzle, route, const Offset(1.75, .5));
      expect(b.tip, const Offset(1.75, .5));
      expect(b.facing, 0);
      final c = at(tracker, puzzle, route, const Offset(1.95, .5));
      expect(c.tip.dx, closeTo(1.95, 1e-9));
      expect(route, [0, 1], reason: 'the route is untouched');
    });

    test('all four cardinal directions', () {
      final puzzle = open4();
      // Cell 5 is (1, 1); centre (1.5, 1.5). Reach in every direction.
      final route = [0, 4, 5];
      final cases = {
        'right': (const Offset(1.5 + .3, 1.5), 0, const Offset(1.8, 1.5)),
        'down': (const Offset(1.5, 1.5 + .3), 1, const Offset(1.5, 1.8)),
        'left': (const Offset(1.5 - .3, 1.5), 2, const Offset(1.2, 1.5)),
        'up': (const Offset(1.5, 1.5 - .3), 3, const Offset(1.5, 1.2)),
      };
      for (final entry in cases.entries) {
        final fresh = TipTracker();
        final v = at(
          fresh,
          puzzle,
          route,
          entry.value.$1,
          facing: entry.value.$2,
          canEnter: (_) => true,
        );
        expect(v.tip.dx, closeTo(entry.value.$3.dx, 1e-9), reason: entry.key);
        expect(v.tip.dy, closeTo(entry.value.$3.dy, 1e-9), reason: entry.key);
        expect(v.facing, entry.value.$2, reason: entry.key);
      }
    });

    test('a diagonal finger projects onto one axis', () {
      final puzzle = open4();
      final v = at(tracker, puzzle, [0, 1], const Offset(1.5 + .3, .5 + .12));
      expect(v.tip.dy, .5, reason: 'no vertical component');
      expect(v.tip.dx, closeTo(1.8, 1e-9));
    });

    test('the sideways dead zone keeps the axis stable', () {
      final puzzle = open4();
      at(tracker, puzzle, [0, 1], const Offset(1.7, .5));
      final v = at(tracker, puzzle, [0, 1], const Offset(1.7, .5 + .25));
      expect(v.tip.dy, .5, reason: 'still horizontal');
      final turned = at(tracker, puzzle, [0, 1], const Offset(1.55, .5 + .45));
      expect(turned.tip.dx, 1.5, reason: 'now vertical');
      expect(turned.facing, 1);
    });

    test(
      'the facing never flickers on small jitter, and flips on a real retreat',
      () {
        final puzzle = open4();
        at(tracker, puzzle, [0, 1], const Offset(1.5, .5));
        expect(at(tracker, puzzle, [0, 1], const Offset(1.8, .5)).facing, 0);
        expect(at(tracker, puzzle, [0, 1], const Offset(1.74, .5)).facing, 0);
        final back = at(tracker, puzzle, [0, 1], const Offset(1.62, .5));
        expect(
          back.facing,
          2,
          reason: 'the finger retreated by more than 0.10',
        );
        expect(
          back.tip.dx,
          closeTo(1.62, 1e-9),
          reason: 'the tip does not jump',
        );
      },
    );

    test('rendered facing and tip are always cardinal under random input', () {
      final puzzle = open4();
      final random = math.Random(7);
      final route = [0, 1, 5];
      for (var i = 0; i < 2000; i++) {
        final pointer = Offset(
          1.5 + random.nextDouble() * 1.6 - .8,
          1.5 + random.nextDouble() * 1.6 - .8,
        );
        final v = at(tracker, puzzle, route, pointer, facing: 1);
        expect(v.facing, inInclusiveRange(0, 3));
        expect(
          v.tip.dx == v.center.dx || v.tip.dy == v.center.dy,
          isTrue,
          reason: 'diagonal tip at $pointer',
        );
      }
    });
  });

  group('cell acceptance', () {
    test('the tip does not move when the next cell is accepted', () {
      final puzzle = open4();
      final before = at(tracker, puzzle, [0, 1], const Offset(1.999, .5));
      final after = at(tracker, puzzle, [0, 1, 2], const Offset(2.001, .5));
      expect((after.tip - before.tip).distance, lessThan(.01));
      expect(before.facing, after.facing);
      expect(after.trim, isTrue, reason: 'the tip is still on the old segment');
    });

    test('continuing past the new centre switches to a leading segment', () {
      final puzzle = open4();
      at(tracker, puzzle, [0, 1], const Offset(1.999, .5));
      at(tracker, puzzle, [0, 1, 2], const Offset(2.2, .5));
      final v = at(tracker, puzzle, [0, 1, 2], const Offset(2.7, .5));
      expect(v.trim, isFalse);
      expect(v.tip.dx, closeTo(2.7, 1e-9));
    });

    test(
      'a fast multi-cell drag still ends at the finger on the last cell',
      () {
        final puzzle = open4();
        at(tracker, puzzle, [0], const Offset(.6, .5));
        final v = at(
          tracker,
          puzzle,
          [0, 1, 2, 3],
          const Offset(3.4, .5),
          canEnter: (_) => true,
        );
        expect(v.cell, 3);
        expect(v.tip.dx, lessThanOrEqualTo(3.5 + 1e-9));
        expect(v.tip.dy, v.center.dy);
      },
    );
  });

  group('obstacles', () {
    test('a wall stops the tip short of the boundary', () {
      final puzzle = open4(walls: [(1, 2)]);
      final v = at(tracker, puzzle, [0, 1], const Offset(1.97, .5));
      expect(v.tip.dx, lessThan(1.5 + .5 - .22 + 1e-9));
      expect(v.tip.dx, greaterThan(1.5));
    });

    test('a locked gate or wrong checkpoint blocks the same way', () {
      final puzzle = open4();
      final v = at(
        tracker,
        puzzle,
        [0, 1],
        const Offset(1.99, .5),
        canEnter: (_) => false,
      );
      expect(v.tip.dx, lessThan(1.98));
      final open = at(
        TipTracker(),
        puzzle,
        [0, 1],
        const Offset(1.99, .5),
        canEnter: (_) => true,
      );
      expect(open.tip.dx, closeTo(1.99, 1e-9));
    });

    test('visited tiles and the board edge block the tip', () {
      final puzzle = open4();
      // Cell 3 is the top-right corner: nothing to the right or above.
      final edge = at(
        tracker,
        puzzle,
        [0, 1, 2, 3],
        const Offset(3.5 + .45, .5),
        canEnter: (_) => true,
      );
      expect(edge.tip.dx, lessThan(3.5 + .3));
      // Cell 0 is on the route but is not the cell just left, so it is blocked.
      final visited = at(TipTracker(), puzzle, [
        0,
        4,
        5,
        1,
      ], const Offset(1.5 - .45, .5));
      expect(visited.tip.dx, greaterThan(1.5 - .3));
    });
  });

  group('backtracking', () {
    test('retreating keeps the tip on the trail and flips the facing', () {
      final puzzle = open4();
      final route = [0, 1, 2];
      at(tracker, puzzle, route, const Offset(2.2, .5));
      final v = at(tracker, puzzle, route, const Offset(2.05, .5));
      expect(v.facing, 2);
      expect(v.trim, isTrue);
      expect(v.tip.dx, closeTo(2.05, 1e-9));
    });

    test('accepting the retraction does not move the tip', () {
      final puzzle = open4();
      final before = at(tracker, puzzle, [0, 1, 2], const Offset(2.001, .5));
      final after = at(tracker, puzzle, [0, 1], const Offset(1.999, .5));
      expect((after.tip - before.tip).distance, lessThan(.01));
      expect(after.facing, 2);
    });
  });

  group('automatic movement', () {
    test('after a slide the tip waits on the accepted cell', () {
      final puzzle = open4();
      at(tracker, puzzle, [0, 1], const Offset(1.99, .5));
      // The route jumps by several cells (ice).
      final v = at(
        tracker,
        puzzle,
        [0, 1, 2, 3],
        const Offset(2.2, .5),
        canEnter: (_) => true,
      );
      expect(v.tip.dx, closeTo(v.center.dx + 0, 1.0));
      final waiting = at(
        tracker,
        puzzle,
        [0, 1, 2, 3],
        const Offset(2.2, .5),
        canEnter: (_) => true,
      );
      expect(waiting.extension, 0);
    });

    test('portal transport never produces a diagonal or a jump back', () {
      final puzzle = Puzzle(4, [0, 15], portal: (1, 14));
      at(tracker, puzzle, [0, 1], const Offset(1.6, .5));
      final jumped = at(
        tracker,
        puzzle,
        [0, 1, 14],
        const Offset(1.9, .5),
        facing: 0,
        canEnter: (_) => true,
      );
      expect(jumped.tip, jumped.center, reason: 'waits on the exit');
      expect(jumped.trim, isFalse);
      // Finger arrives at the exit and carries on from there.
      final arrived = at(
        tracker,
        puzzle,
        [0, 1, 14],
        const Offset(2.55, 3.5),
        facing: 0,
        canEnter: (_) => true,
      );
      expect(arrived.tip.dy, arrived.center.dy);
      expect((arrived.tip - arrived.center).distance, lessThan(.6));
    });
  });

  group('checkpoints', () {
    test('the tip rests on the leading rim and never on the number', () {
      final puzzle = Puzzle(4, [0, 5, 15]);
      final route = [0, 1, 5];
      final v = at(tracker, puzzle, route, const Offset(1.5, 1.5), facing: 1);
      expect(v.tip.dx, 1.5);
      expect(v.tip.dy, closeTo(1.5 + tracker.checkpointLead, 1e-9));
      expect(v.facing, 1);
    });

    test('the lead is continuous as the finger moves', () {
      final puzzle = Puzzle(4, [0, 5, 15]);
      final route = [0, 1, 5];
      var previous = at(
        tracker,
        puzzle,
        route,
        const Offset(1.5, 1.2),
        facing: 1,
      );
      for (var y = 1.2; y <= 1.99; y += .01) {
        final v = at(tracker, puzzle, route, Offset(1.5, y), facing: 1);
        expect(
          (v.tip - previous.tip).distance,
          lessThan(.05),
          reason: 'jump at y=$y',
        );
        previous = v;
      }
    });

    test(
      'the tip size does not depend on whether the cell is a checkpoint',
      () {
        final puzzle = Puzzle(4, [0, 5, 15]);
        final ordinary = at(tracker, puzzle, [0, 1], const Offset(1.9, .5));
        final onCheckpoint = at(
          TipTracker(),
          puzzle,
          [0, 1, 5],
          const Offset(1.5, 1.95),
          facing: 1,
        );
        expect(ordinary.extension, greaterThan(0));
        expect(onCheckpoint.extension, greaterThan(0));
      },
    );
  });

  group('lifecycle', () {
    test('reset forgets gesture state', () {
      final puzzle = open4();
      at(tracker, puzzle, [0, 1], const Offset(1.9, .5));
      tracker.reset();
      final v = at(tracker, puzzle, [0, 1], const Offset(1.5, .5), facing: 3);
      expect(v.facing, 3);
    });

    test('the resting tip faces the accepted direction', () {
      final puzzle = open4();
      final v = TipTracker.rest(puzzle, [0, 4], 1);
      expect(v.tip, v.center);
      expect(v.facing, 1);
    });
  });
}
