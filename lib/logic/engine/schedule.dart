import 'dart:math' as math;

import '../puzzle_profile.dart';
import '../puzzle_random.dart';
import 'spec.dart';

/// The first campaign level of each mechanic. The mechanic appears alone
/// there, is practised for [practiceLevels] levels, and then joins the pool.
const wallsIntro = 21;
const iceIntro = 61;
const gateIntro = 101;
const portalIntro = 141;
const practiceLevels = 9;

/// From this level two or more mechanics may share a board.
const comboStart = 181;

const _wallArchetypes = [
  Archetype.corridors,
  Archetype.chambers,
  Archetype.bottleneck,
  Archetype.interlock,
];

/// Where a level sits in the long difficulty curve, from 0 to about 0.9. It
/// rises quickly at first, then levels off so late levels stay playable.
double baseDifficulty(int level) =>
    math.min(0.9, 1 - math.exp(-(level - 1) / 320));

/// Offsets inside each block of ten levels. Difficulty comes in waves: a
/// breather every few levels and a hard one at the end of the block.
const _wave = [0.0, 0.05, 0.1, -0.04, 0.12, 0.17, 0.06, 0.2, -0.12, 0.26];

DifficultyBand _bandFor(double target) {
  if (target < 0.1) return DifficultyBand.beginner;
  if (target < 0.24) return DifficultyBand.easy;
  if (target < 0.42) return DifficultyBand.intermediate;
  if (target < 0.6) return DifficultyBand.advanced;
  if (target < 0.78) return DifficultyBand.expert;
  return DifficultyBand.master;
}

int _sizeFor(DifficultyBand band, int level, PuzzleRandom rng) {
  final options = switch (band) {
    DifficultyBand.beginner => [4, 4, 5],
    DifficultyBand.easy => [4, 5, 5],
    DifficultyBand.intermediate => [5, 5, 6],
    DifficultyBand.advanced => [5, 6, 6, 7],
    DifficultyBand.expert => [6, 7, 7],
    DifficultyBand.master => [7],
  };
  final cap = level <= 12
      ? 4
      : level <= 30
      ? 5
      : level <= 80
      ? 6
      : 7;
  return math.min(cap, rng.pick(options));
}

/// The deterministic spec for campaign level [level].
PuzzleSpec campaignSpec(int level) {
  final rng = PuzzleRandom(puzzleSeed('pathwise-schedule/campaign/$level'));
  final block = (level - 1) % 10;
  final target = (baseDifficulty(level) + _wave[block] * 0.8).clamp(0.0, 0.92);
  var band = _bandFor(target);
  final id = 'campaign/$level';

  PuzzleSpec spec({
    required Archetype archetype,
    bool walls = false,
    bool ice = false,
    bool gate = false,
    bool portal = false,
    DifficultyBand? forced,
    int? size,
    CheckpointStyle? style,
  }) {
    final chosen = forced ?? band;
    final hard = chosen.index >= DifficultyBand.intermediate.index;
    final minimum = (gate || portal || ice || (walls && hard)) ? 5 : 4;
    final cells = math.max(minimum, size ?? _sizeFor(chosen, level, rng));
    return PuzzleSpec(
      id: id,
      kind: GenerationKind.campaign,
      size: cells,
      band: chosen,
      archetype: archetype,
      walls: walls,
      ice: ice,
      gate: gate,
      portal: portal,
      style:
          style ??
          (block == 8 || block == 3
              ? CheckpointStyle.guided
              : block == 9
              ? CheckpointStyle.sparse
              : CheckpointStyle.standard),
    );
  }

  PuzzleSpec single(String mechanic) => switch (mechanic) {
    'walls' => spec(archetype: rng.pick(_wallArchetypes), walls: true),
    'ice' => spec(archetype: Archetype.directional, ice: true),
    'gate' => spec(archetype: Archetype.keyed, gate: true),
    _ => spec(archetype: Archetype.wormhole, portal: true),
  };

  // An introduction: the mechanic alone, on a small board with plenty of
  // checkpoints, so the tutorial and the first board agree.
  if (level == wallsIntro) {
    return spec(
      archetype: Archetype.corridors,
      walls: true,
      forced: DifficultyBand.easy,
      size: 5,
      style: CheckpointStyle.guided,
    );
  }
  if (level == iceIntro) {
    return spec(
      archetype: Archetype.directional,
      ice: true,
      forced: DifficultyBand.easy,
      size: 5,
      style: CheckpointStyle.guided,
    );
  }
  if (level == gateIntro) {
    return spec(
      archetype: Archetype.keyed,
      gate: true,
      forced: DifficultyBand.easy,
      size: 5,
      style: CheckpointStyle.guided,
    );
  }
  if (level == portalIntro) {
    return spec(
      archetype: Archetype.wormhole,
      portal: true,
      forced: DifficultyBand.easy,
      size: 5,
      style: CheckpointStyle.guided,
    );
  }

  if (level < wallsIntro) {
    // Open boards: checkpoint order and parity.
    if (level <= 6) band = DifficultyBand.beginner;
    return spec(archetype: Archetype.openOrder);
  }

  // Mechanics unlocked so far, in the order they were introduced.
  final unlocked = <String>[
    if (level >= wallsIntro) 'walls',
    if (level >= iceIntro) 'ice',
    if (level >= gateIntro) 'gate',
    if (level >= portalIntro) 'portal',
  ];
  // A mechanic is practised alone for a while after it arrives.
  for (final entry in const [
    ('portal', portalIntro),
    ('gate', gateIntro),
    ('ice', iceIntro),
    ('walls', wallsIntro),
  ]) {
    if (level > entry.$2 && level <= entry.$2 + practiceLevels) {
      return single(entry.$1);
    }
  }

  // After the introductions: a mix of single mechanics and combinations.
  final roll = rng.nextInt(100);
  final allowCombos = level >= comboStart;
  final comboChance = level >= 261 ? 55 : 35;
  if (roll < 12 && level > 40) {
    return spec(archetype: Archetype.openOrder);
  }
  if (!allowCombos || roll >= 12 + comboChance) {
    return single(rng.pick(unlocked));
  }
  final pool = [...unlocked];
  rng.shuffle(pool);
  final count = level >= 261 && rng.chance(30) ? 3 : 2;
  final chosen = pool.take(math.min(count, pool.length)).toSet();
  return spec(
    archetype: Archetype.mixed,
    walls: chosen.contains('walls'),
    ice: chosen.contains('ice'),
    gate: chosen.contains('gate'),
    portal: chosen.contains('portal'),
  );
}

/// Difficulty bands for the three Daily checkpoints and the daily board.
const _dailyBands = [
  DifficultyBand.easy,
  DifficultyBand.intermediate,
  DifficultyBand.advanced,
  DifficultyBand.expert,
];

int _dayNumber(String day) {
  final parts = day.split('-');
  final date = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  return date.difference(DateTime.utc(2025)).inDays;
}

/// The deterministic spec for a Daily Challenge board. [checkpoint] is 1–3
/// for the warm-up boards and null for the daily board itself.
PuzzleSpec dailySpec(String day, int? checkpoint) {
  final number = _dayNumber(day);
  final stage = checkpoint == null ? 3 : checkpoint - 1;
  final id = checkpoint == null ? 'daily/$day' : 'daily/$day/$checkpoint';
  final size = checkpoint == null ? 6 : 3 + checkpoint;
  final theme = number % 7;
  final band = _dailyBands[stage];
  // Warm-up boards stay readable: open or wall-only. The daily board carries
  // the day's theme.
  if (stage < 3) {
    final walls = stage >= 1 && (number + stage) % 3 != 0;
    return PuzzleSpec(
      id: id,
      kind: GenerationKind.daily,
      size: size,
      band: band,
      archetype: walls
          ? _wallArchetypes[(number + stage) % _wallArchetypes.length]
          : Archetype.openOrder,
      walls: walls,
      style: CheckpointStyle.guided,
    );
  }
  return switch (theme) {
    0 => PuzzleSpec(
      id: id,
      kind: GenerationKind.daily,
      size: size,
      band: band,
      archetype: Archetype.corridors,
      walls: true,
    ),
    1 => PuzzleSpec(
      id: id,
      kind: GenerationKind.daily,
      size: size,
      band: band,
      archetype: Archetype.chambers,
      walls: true,
    ),
    2 => PuzzleSpec(
      id: id,
      kind: GenerationKind.daily,
      size: size,
      band: band,
      archetype: Archetype.directional,
      ice: true,
    ),
    3 => PuzzleSpec(
      id: id,
      kind: GenerationKind.daily,
      size: size,
      band: band,
      archetype: Archetype.keyed,
      gate: true,
    ),
    4 => PuzzleSpec(
      id: id,
      kind: GenerationKind.daily,
      size: size,
      band: band,
      archetype: Archetype.wormhole,
      portal: true,
    ),
    5 => PuzzleSpec(
      id: id,
      kind: GenerationKind.daily,
      size: size,
      band: band,
      archetype: Archetype.bottleneck,
      walls: true,
    ),
    _ => PuzzleSpec(
      id: id,
      kind: GenerationKind.daily,
      size: size,
      band: band,
      archetype: Archetype.mixed,
      walls: true,
      ice: true,
    ),
  };
}

/// The deterministic spec for Time Attack board [index] of a run.
///
/// Time Attack favours quick reading: open boards and a few simple walls,
/// short deductions, and no mechanics that need a tutorial.
PuzzleSpec attackSpec(String key, int index) {
  final size = (4 + index ~/ 3).clamp(4, 7);
  final layout = index < 3 ? 2 : index % 3;
  final style = switch (layout) {
    0 => CheckpointStyle.guided,
    1 => CheckpointStyle.sparse,
    _ => CheckpointStyle.standard,
  };
  final band = size <= 4
      ? DifficultyBand.beginner
      : size == 5
      ? DifficultyBand.easy
      : DifficultyBand.intermediate;
  final walls = index >= 3 && index.isEven;
  return PuzzleSpec(
    id: 'attack/$key',
    kind: GenerationKind.attack,
    size: size,
    band: band,
    archetype: walls ? Archetype.corridors : Archetype.openOrder,
    walls: walls,
    style: style,
  );
}
