import '../puzzle_profile.dart';
import '../puzzle_random.dart';

/// Bumped whenever a change would alter the boards a spec generates.
const generationVersion = 2;

/// How densely checkpoints are kept once the board can be solved by logic.
enum CheckpointStyle {
  /// More checkpoints than needed. The route is easy to see.
  guided,

  /// The fewest checkpoints that keep the band's difficulty ceiling.
  standard,

  /// Pushes towards the ceiling: as few checkpoints as logic allows.
  sparse,
}

/// Which product mode a board is generated for. It changes budgets and
/// readability limits, never the movement rules.
enum GenerationKind { campaign, daily, attack }

/// Everything the generator needs to build one board. Two equal specs always
/// produce the same board on every device.
final class PuzzleSpec {
  const PuzzleSpec({
    required this.id,
    required this.kind,
    required this.size,
    required this.band,
    required this.archetype,
    this.walls = false,
    this.ice = false,
    this.gate = false,
    this.portal = false,
    this.style = CheckpointStyle.standard,
  });

  /// The stable puzzle identity, such as `campaign/37`.
  final String id;
  final GenerationKind kind;
  final int size;
  final DifficultyBand band;
  final Archetype archetype;
  final bool walls;
  final bool ice;
  final bool gate;
  final bool portal;
  final CheckpointStyle style;

  int get seed => puzzleSeed('pathwise-engine-$generationVersion/$id');

  int get mechanicCount =>
      [walls, ice, gate, portal].where((enabled) => enabled).length;

  /// A key that is equal for equal specs, for caches and request merging.
  String get key =>
      '$generationVersion/$id/$size/${band.name}/${archetype.name}/'
      '${walls ? 'w' : ''}${ice ? 'i' : ''}${gate ? 'g' : ''}'
      '${portal ? 'p' : ''}/${style.name}';

  @override
  bool operator ==(Object other) => other is PuzzleSpec && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}
