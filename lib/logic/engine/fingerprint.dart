import '../puzzle.dart';

int _mapCell(int cell, int size, int variant) {
  var x = cell % size;
  var y = cell ~/ size;
  if (variant >= 4) x = size - 1 - x;
  for (var turn = 0; turn < variant % 4; turn++) {
    final oldX = x;
    x = size - 1 - y;
    y = oldX;
  }
  return y * size + x;
}

/// The board after applying one of the eight rotations and reflections.
/// Walls are normalised, so equal boards give equal lists.
({
  List<int> checkpoints,
  List<int> walls,
  List<int> ice,
  (int, int)? gate,
  (int, int)? portal,
})
_variant(Puzzle p, int variant) {
  int map(int cell) => _mapCell(cell, p.size, variant);
  final walls = [
    for (final (a, b) in p.walls)
      (map(a) < map(b) ? map(a) * 64 + map(b) : map(b) * 64 + map(a)),
  ]..sort();
  final portal = p.portal;
  final a = portal == null ? 0 : map(portal.$1);
  final b = portal == null ? 0 : map(portal.$2);
  return (
    checkpoints: [for (final cell in p.checkpoints) map(cell)],
    walls: walls,
    ice: [for (final cell in p.iceTiles) map(cell)]..sort(),
    gate: p.gate == null ? null : (map(p.gate!.$1), map(p.gate!.$2)),
    portal: portal == null ? null : (a < b ? (a, b) : (b, a)),
  );
}

/// A text identity that is the same for a board and all eight of its
/// rotations and reflections.
String canonicalBoard(Puzzle p) {
  String? best;
  for (var variant = 0; variant < 8; variant++) {
    final v = _variant(p, variant);
    final text =
        '${p.size}|${v.checkpoints.join(',')}|${v.walls.join(',')}|'
        '${v.ice.join(',')}|${v.gate ?? ''}|${v.portal ?? ''}';
    if (best == null || text.compareTo(best) < 0) best = text;
  }
  return best!;
}

double _jaccard(Set<int> a, Set<int> b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final shared = a.intersection(b).length;
  return shared / (a.length + b.length - shared);
}

/// How alike two boards of the same size are, from 0 to 1, taking the best of
/// the eight symmetries. It compares walls, ice and checkpoint cells, so boards
/// that only shift a clue or two score close to 1.
double boardSimilarity(Puzzle a, Puzzle b) {
  if (a.size != b.size) return 0;
  final other = _variant(b, 0);
  var best = 0.0;
  for (var variant = 0; variant < 8; variant++) {
    final v = _variant(a, variant);
    final walls = _jaccard(v.walls.toSet(), other.walls.toSet());
    final ice = _jaccard(v.ice.toSet(), other.ice.toSet());
    final clues = _jaccard(v.checkpoints.toSet(), other.checkpoints.toSet());
    final score = 0.45 * walls + 0.15 * ice + 0.4 * clues;
    if (score > best) best = score;
  }
  return best;
}
