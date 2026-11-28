import 'dart:io';

import '../lib/logic/engine/render.dart';
import '../lib/logic/engine/schedule.dart';
import '../lib/logic/puzzle.dart';
import '../lib/logic/puzzle_generator.dart';
import '../lib/logic/puzzle_profile.dart';

/// Generates boards and prints them with their measurements.
///
///     dart run tool/puzzle_lab.dart campaign 1 40 1
///     dart run tool/puzzle_lab.dart grid 6
void main(List<String> args) {
  final mode = args.isEmpty ? 'campaign' : args[0];
  switch (mode) {
    case 'campaign':
      final first = int.parse(args[1]);
      final count = int.parse(args[2]);
      final step = args.length > 3 ? int.parse(args[3]) : 1;
      final detail = args.length > 4 && args[4] == 'detail';
      final specs = [
        for (var i = 0; i < count; i++) campaignSpec(first + i * step),
      ];
      run(specs, detail: detail, quiet: args.length > 4 && args[4] == 'quiet');
    case 'grid':
      final seeds = int.parse(args[1]);
      run(
        gridSpecs(seeds),
        detail: args.length > 2 && args[2] == 'detail',
        quiet: args.length > 2 && args[2] == 'quiet',
      );
    default:
      stderr.writeln('unknown mode $mode');
      exitCode = 2;
  }
}

List<PuzzleSpec> gridSpecs(int seeds) {
  final specs = <PuzzleSpec>[];
  const mechanics = [
    (Archetype.openOrder, false, false, false, false),
    (Archetype.corridors, true, false, false, false),
    (Archetype.chambers, true, false, false, false),
    (Archetype.bottleneck, true, false, false, false),
    (Archetype.interlock, true, false, false, false),
    (Archetype.directional, false, true, false, false),
    (Archetype.keyed, false, false, true, false),
    (Archetype.wormhole, false, false, false, true),
    (Archetype.mixed, true, true, true, false),
  ];
  for (final band in DifficultyBand.values) {
    for (final (archetype, walls, ice, gate, portal) in mechanics) {
      for (final size in const [4, 5, 6, 7]) {
        for (var seed = 0; seed < seeds; seed++) {
          specs.add(
            PuzzleSpec(
              id: 'lab/${band.name}/${archetype.name}/$size/$seed',
              kind: GenerationKind.campaign,
              size: size,
              band: band,
              archetype: archetype,
              walls: walls,
              ice: ice,
              gate: gate,
              portal: portal,
            ),
          );
        }
      }
    }
  }
  return specs;
}

void run(
  List<PuzzleSpec> specs, {
  required bool detail,
  bool quiet = false,
}) {
  final byBand = <String, List<double>>{};
  final fallbackBy = <String, List<int>>{};
  final summary = <String, List<int>>{};
  final reasons = <String, int>{};
  var fallbacks = 0;
  var total = 0;
  final times = <int>[];
  for (final spec in specs) {
    final stats = GenerationStats();
    final watch = Stopwatch()..start();
    String? failure;
    VerifiedPuzzle? board;
    try {
      board = generatePuzzle(spec, stats: stats);
    } catch (error) {
      failure = '$error';
    }
    watch.stop();
    total++;
    times.add(watch.elapsedMilliseconds);
    for (final entry in stats.rejections.entries) {
      reasons.update(
        entry.key,
        (n) => n + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    final profile = board?.profile;
    if (stats.fallback > 0) fallbacks++;
    final group = '${spec.band.name}/${spec.archetype.name}/${spec.size}';
    final tally = summary.putIfAbsent(group, () => [0, 0, 0]);
    tally[0]++;
    if (stats.fallback > 0) tally[1]++;
    tally[2] += watch.elapsedMilliseconds;
    final mechanics = [
      if (spec.walls) 'walls',
      if (spec.ice) 'ice',
      if (spec.gate) 'gate',
      if (spec.portal) 'portal',
    ].join('+');
    final head =
        '### ${spec.id} ${spec.size}x${spec.size} want=${spec.band.name} '
        '${spec.archetype.name} [$mechanics] ${spec.style.name} '
        '${watch.elapsedMilliseconds}ms attempts=${stats.attempts} '
        'accepted=${stats.accepted} fallback=${stats.fallback} '
        'solver=${stats.solverCalls}/${stats.solverNodes} '
        'deduce=${stats.deduceCalls}';
    if (!quiet) stdout.writeln(head);
    if (failure != null || board == null) {
      stdout.writeln('  FAILED: $failure');
      continue;
    }
    if (profile != null) {
      byBand.putIfAbsent(spec.band.name, () => []).add(profile.difficulty);
      final fb = fallbackBy.putIfAbsent(spec.band.name, () => [0, 0]);
      fb[0]++;
      if (stats.fallback > 0) fb[1]++;
    }
    if (quiet) {
      if (profile != null) {
        stdout.writeln(
          '${spec.id} want=${spec.band.name} got=${profile.band.name} '
          'D=${profile.difficulty.toStringAsFixed(1)} t=${profile.hardestTier} '
          'fb=${stats.fallback} ms=${watch.elapsedMilliseconds} '
          'clues=${board.puzzle.checkpoints.length}',
        );
      }
      continue;
    }
    if (profile != null) {
      stdout.writeln(
        '  got=${profile.band.name} diff=${profile.difficulty.toStringAsFixed(1)} '
        'tier=${profile.hardestTier} steps=${profile.deductionSteps} '
        'depth=${profile.chainDepth} forced=${profile.forcedMoveRatio.toStringAsFixed(2)} '
        'traps=${profile.trapCount}/${profile.trapDepth} '
        'clues=${board.puzzle.checkpoints.length} walls=${board.puzzle.walls.length} '
        'expect=${profile.expectedSolveMs}ms',
      );
      stdout.writeln('  techniques=${profile.techniques}');
      stdout.writeln(
        '  parts=${[for (final f in profile.formations) '${f.kind}:${f.cells}:${f.relevance.name}']}',
      );
    }
    if (detail) {
      stdout.writeln(describeBoard(board.puzzle));
      stdout.writeln(describeBoard(board.puzzle, route: board.solution));
    } else {
      stdout.writeln(describeBoard(board.puzzle));
    }
  }
  times.sort();
  stdout.writeln('=====SUMMARY=====');
  for (final entry in byBand.entries) {
    final values = entry.value..sort();
    final fb = fallbackBy[entry.key]!;
    stdout.writeln(
      'band ${entry.key}: n=${values.length} D min=${values.first.toStringAsFixed(1)} '
      'p25=${values[values.length ~/ 4].toStringAsFixed(1)} '
      'med=${values[values.length ~/ 2].toStringAsFixed(1)} '
      'p75=${values[values.length * 3 ~/ 4].toStringAsFixed(1)} '
      'max=${values.last.toStringAsFixed(1)} fallback=${fb[1]}/${fb[0]}',
    );
  }
  stdout.writeln(
    'boards=$total fallbacks=$fallbacks median=${times[times.length ~/ 2]}ms '
    'p95=${times[(times.length * 0.95).floor().clamp(0, times.length - 1)]}ms '
    'max=${times.last}ms',
  );
  stdout.writeln('rejections=$reasons');
  for (final entry in summary.entries) {
    final v = entry.value;
    stdout.writeln(
      '${entry.key}: n=${v[0]} fallback=${v[1]} meanMs=${(v[2] / v[0]).round()}',
    );
  }
}
