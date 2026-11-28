import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pathwise/logic/puzzle.dart';
import 'package:pathwise/logic/tip_tracker.dart';

// 4 x 4, cells numbered row by row. Cell 1 centre is (1.5, 0.5).
Puzzle open4({List<(int, int)> walls = const [], (int, int)? gate}) =>
    Puzzle(4, [0, 15], walls: walls, gate: gate);

TipVisual at(
  TipTracker tracker,
  Puzzle puzzle,
  List<int> route,
  Offset pointer, {
  bool Function(int)? canEnter,
}) => tracker.update(
  puzzle: puzzle,
  route: route,
  pointer: pointer,
  canEnter: canEnter ?? (cell) => !route.contains(cell),
);

void main() {
  late TipTracker tracker;
  setUp(() => tracker = TipTracker());

  test('rest centers on normal cells and clears checkpoint numbers', () {
    final puzzle = open4();
    final normal = TipTracker.rest(puzzle, [0, 4]);
    expect(normal.tip, normal.center);
    expect(normal.extension, 0);

    final checkpoint = TipTracker.rest(puzzle, [0]);
    expect(checkpoint.tip.dx, checkpoint.center.dx);
    expect(checkpoint.tip.dy, closeTo(checkpoint.center.dy - 0.42, 1e-9));
    expect(checkpoint.extension, 0.42);
  });

  group('continuous tracking before a cell is accepted', () {
    test('horizontal: the tip follows the finger between cell centres', () {
      final puzzle = open4();
      final route = [0, 1];
      final a = at(tracker, puzzle, route, const Offset(1.5, .5));
      expect(a.tip, const Offset(1.5, .5));
      final b = at(tracker, puzzle, route, const Offset(1.75, .5));
      expect(b.tip, const Offset(1.75, .5));
      final c = at(tracker, puzzle, route, const Offset(1.95, .5));
      expect(c.tip.dx, closeTo(1.95, 1e-9));
      expect(route, [0, 1], reason: 'the route is untouched');
    });

    test('all four cardinal directions', () {
      final puzzle = open4();
      // Cell 5 is (1, 1); centre (1.5, 1.5). Reach in every direction.
      final route = [0, 4, 5];
      final cases = {
        'right': (const Offset(1.5 + .3, 1.5), const Offset(1.8, 1.5)),
        'down': (const Offset(1.5, 1.5 + .3), const Offset(1.5, 1.8)),
        'left': (const Offset(1.5 - .3, 1.5), const Offset(1.2, 1.5)),
        'up': (const Offset(1.5, 1.5 - .3), const Offset(1.5, 1.2)),
      };
      for (final entry in cases.entries) {
        final fresh = TipTracker();
        final v = at(
          fresh,
          puzzle,
          route,
          entry.value.$1,
          canEnter: (_) => true,
        );
        expect(v.tip.dx, closeTo(entry.value.$2.dx, 1e-9), reason: entry.key);
        expect(v.tip.dy, closeTo(entry.value.$2.dy, 1e-9), reason: entry.key);
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
    });

    test('rendered tip is always cardinal under random input', () {
      final puzzle = open4();
      final random = math.Random(7);
      final route = [0, 1, 5];
      for (var i = 0; i < 2000; i++) {
        final pointer = Offset(
          1.5 + random.nextDouble() * 1.6 - .8,
          1.5 + random.nextDouble() * 1.6 - .8,
        );
        final v = at(tracker, puzzle, route, pointer);
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
      final edge = at(
        tracker,
        puzzle,
        [0, 1, 2, 3],
        const Offset(3.5 + .45, .5),
        canEnter: (_) => true,
      );
      expect(edge.tip.dx, lessThan(3.5 + .3));
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
    test('retreating keeps the tip on the trail', () {
      final puzzle = open4();
      final route = [0, 1, 2];
      at(tracker, puzzle, route, const Offset(2.2, .5));
      final v = at(tracker, puzzle, route, const Offset(2.05, .5));
      expect(v.trim, isTrue);
      expect(v.tip.dx, closeTo(2.05, 1e-9));
    });

    test('accepting the retraction does not move the tip', () {
      final puzzle = open4();
      final before = at(tracker, puzzle, [0, 1, 2], const Offset(2.001, .5));
      final after = at(tracker, puzzle, [0, 1], const Offset(1.999, .5));
      expect((after.tip - before.tip).distance, lessThan(.01));
    });
  });

  group('automatic movement', () {
    test('after a slide the tip waits on the accepted cell', () {
      final puzzle = open4();
      at(tracker, puzzle, [0, 1], const Offset(1.99, .5));
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
        canEnter: (_) => true,
      );
      expect(jumped.tip, jumped.center, reason: 'waits on the exit');
      expect(jumped.trim, isFalse);
      final arrived = at(
        tracker,
        puzzle,
        [0, 1, 14],
        const Offset(2.55, 3.5),
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
      final v = at(tracker, puzzle, route, const Offset(1.5, 1.5));
      expect(v.tip.dx, 1.5);
      expect(v.tip.dy, closeTo(1.5 - tracker.checkpointLead, 1e-9));
    });

    test('the lead is continuous as the finger moves', () {
      final puzzle = Puzzle(4, [0, 5, 15]);
      final route = [0, 1, 5];
      var previous = at(tracker, puzzle, route, const Offset(1.5, 1.2));
      for (var y = 1.2; y <= 1.99; y += .01) {
        final v = at(tracker, puzzle, route, Offset(1.5, y));
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
        final onCheckpoint = at(TipTracker(), puzzle, [
          0,
          1,
          5,
        ], const Offset(1.5, 1.95));
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
      final v = at(tracker, puzzle, [0, 1], const Offset(1.5, .5));
      expect(v.tip, v.center);
    });
  });

  test('TipTracker stops short of out-of-bounds, walls, and closed gates', () {
    // 3x3 board, start at 0, wall between 0 and 1, only legal move is down (1 -> cell 3).
    final puzzle = Puzzle(3, [0, 8], walls: [(0, 1)]);
    final tracker = TipTracker();

    final rightDrag = tracker.update(
      puzzle: puzzle,
      route: const [0],
      pointer: const Offset(0.85, 0.5),
      canEnter: (c) => c == 3,
    );
    expect(rightDrag.tip.dx, lessThan(0.85));

    final upDrag = tracker.update(
      puzzle: puzzle,
      route: const [0],
      pointer: const Offset(0.5, 0.15),
      canEnter: (c) => c == 3,
    );
    expect(upDrag.tip.dy, closeTo(0.08, 1e-9));

    final leftDrag = tracker.update(
      puzzle: puzzle,
      route: const [0],
      pointer: const Offset(0.15, 0.5),
      canEnter: (c) => c == 3,
    );
    expect(leftDrag.tip.dx, greaterThan(0.15));
  });

  test(
    'TipTracker.rest centers on normal cells and offsets above checkpoints',
    () {
      final puzzle = Puzzle(3, [0, 8]);
      final rest = TipTracker.rest(puzzle, const [0]);
      expect(rest.tip.dx, rest.center.dx);
      expect(rest.tip.dy, closeTo(rest.center.dy - 0.42, 1e-9));
      expect(rest.extension, 0.42);
    },
  );
}
