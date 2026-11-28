/// Fixed integer PRNG so puzzle identities stay stable across SDK upgrades,
/// devices and isolates. A 32-bit mulberry generator; it never reads the
/// clock.
final class PuzzleRandom {
  PuzzleRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  int _next() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = ((t ^ (t >> 15)) * (1 | t)) & 0xFFFFFFFF;
    t = ((t + (((t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF)) ^ t) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  /// A value in `0 <= value < bound`.
  int nextInt(int bound) {
    assert(bound > 0);
    return _next() % bound;
  }

  /// True with probability [percent] in 100.
  bool chance(int percent) => nextInt(100) < percent;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  void shuffle<T>(List<T> items) {
    for (var index = items.length - 1; index > 0; index--) {
      final other = nextInt(index + 1);
      final item = items[index];
      items[index] = items[other];
      items[other] = item;
    }
  }

  /// A new generator whose stream depends only on this one's state and
  /// [salt].
  PuzzleRandom fork(int salt) =>
      PuzzleRandom(((_next() ^ (salt * 0x9E3779B1)) * 0x85EBCA6B) & 0xFFFFFFFF);
}

/// FNV-1a hash of a puzzle identity.
int puzzleSeed(String id) {
  var hash = 0x011c9dc5;
  for (final code in id.codeUnits) {
    hash = ((hash ^ code) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
