import '../puzzle.dart';

/// A text drawing of a board for logs, tests and developer tools.
///
/// Checkpoints show their number, `~` marks ice, `K` and `G` the key and the
/// gate, and `a`/`b` the portal pair. Walls draw as `|` and `---`. With a
/// [route], other cells show the step at which the route visits them.
String describeBoard(Puzzle p, {List<int>? route}) {
  final n = p.size;
  final steps = <int, int>{};
  if (route != null) {
    for (final (index, cell) in route.indexed) {
      steps[cell] = index + 1;
    }
  }
  String label(int cell) {
    final number = p.numbers[cell];
    if (number != 0) return '#$number'.padRight(3);
    if (p.gate?.$1 == cell) return 'K'.padRight(3);
    if (p.gate?.$2 == cell) return 'G'.padRight(3);
    if (p.portal?.$1 == cell) return 'a'.padRight(3);
    if (p.portal?.$2 == cell) return 'b'.padRight(3);
    if (p.iceTiles.contains(cell)) return '~'.padRight(3);
    final step = steps[cell];
    return step == null ? '.'.padRight(3) : '$step'.padRight(3);
  }

  final lines = <String>[];
  final top = StringBuffer('+');
  for (var column = 0; column < n; column++) {
    top.write('---+');
  }
  lines.add(top.toString());
  for (var row = 0; row < n; row++) {
    final cells = StringBuffer('|');
    for (var column = 0; column < n; column++) {
      final cell = row * n + column;
      cells.write(label(cell));
      cells.write(column == n - 1 || p.isWalled(cell, cell + 1) ? '|' : ' ');
    }
    lines.add(cells.toString());
    final below = StringBuffer('+');
    for (var column = 0; column < n; column++) {
      final cell = row * n + column;
      below.write(
        row == n - 1 || p.isWalled(cell, cell + n) ? '---+' : '   +',
      );
    }
    lines.add(below.toString());
  }
  return lines.join('\n');
}
