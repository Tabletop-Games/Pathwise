import 'puzzle.dart';

enum RouteEdit { none, advance, retract }

/// Owns legal route edits, gesture transactions, and the hint state.
final class GameController {
  GameController(this.board) : _path = [board.puzzle.start];

  final VerifiedPuzzle board;
  Puzzle get puzzle => board.puzzle;

  List<int> _path;
  List<int> get path => List.unmodifiable(_path);
  int get tip => _path.last;
  int get length => _path.length;
  int get nextCheckpoint =>
      1 + _path.where((cell) => puzzle.numbers[cell] != 0).length;
  bool get complete => length == puzzle.area && tip == puzzle.finish;

  final _undo = <List<int>>[];
  List<int>? _beforeStroke;
  int? hintCell;
  int hintsUsed = 0;

  bool get isDrawing => _beforeStroke != null;

  bool get canUndo => _undo.isNotEmpty && !complete && _beforeStroke == null;

  bool begin(int cell) {
    if (complete || _beforeStroke != null) return false;
    final index = _path.indexOf(cell);
    if (index == -1 && !canStep(cell)) return false;

    _beforeStroke = List.of(_path);
    if (index >= 0 && index < length - 1) {
      _path.length = index + 1;
      hintCell = null;
    } else if (index < 0) {
      step(cell);
    }
    return true;
  }

  bool canStep(int cell) =>
      !complete &&
      cell >= 0 &&
      cell < puzzle.area &&
      !_path.contains(cell) &&
      puzzle.canExtend(
        tip,
        cell,
        length,
        nextCheckpoint,
        allowEarlyFinish: true,
      );

  RouteEdit step(int cell) {
    if (complete || _beforeStroke == null) return RouteEdit.none;
    if (length > 1 && cell == _path[length - 2]) {
      _path.removeLast();
      hintCell = null;
      return RouteEdit.retract;
    }
    if (!canStep(cell)) return RouteEdit.none;
    _path.add(cell);
    hintCell = null;
    return RouteEdit.advance;
  }

  bool end() {
    final before = _beforeStroke;
    _beforeStroke = null;
    if (before == null || _samePath(before, _path)) return false;
    _remember(before);
    return true;
  }

  bool undo() {
    if (!canUndo) return false;
    _path = _undo.removeLast();
    hintCell = null;
    return true;
  }

  bool clear() {
    if (complete ||
        _beforeStroke != null ||
        (length == 1 && hintCell == null)) {
      return false;
    }
    if (length > 1) _remember(_path);
    _path = [puzzle.start];
    hintCell = null;
    return true;
  }

  bool get routeConflicts =>
      _path.indexed.any((entry) => entry.$2 != board.solution[entry.$1]);

  bool get canHint => !complete && _beforeStroke == null && hintCell == null;

  bool hint({int segment = 1}) {
    if (!canHint) return false;
    var prefix = 1;
    while (prefix < length && _path[prefix] == board.solution[prefix]) {
      prefix++;
    }
    final end = (prefix + segment - 1).clamp(prefix, puzzle.area - 1);
    if (prefix != length || end != prefix) {
      _remember(List.of(_path));
      _path = board.solution.take(end).toList();
    }
    hintCell = board.solution[end];
    hintsUsed++;
    return true;
  }

  void _remember(List<int> before) {
    if (_undo.length == 64) _undo.removeAt(0);
    _undo.add(before);
  }

  static bool _samePath(List<int> left, List<int> right) =>
      left.length == right.length &&
      left.indexed.every((entry) => entry.$2 == right[entry.$1]);

  bool _validPath(List<int> saved) {
    if (saved.isEmpty ||
        saved.first != puzzle.start ||
        saved.length > puzzle.area ||
        saved.toSet().length != saved.length ||
        saved.any((cell) => cell < 0 || cell >= puzzle.area)) {
      return false;
    }
    var checkpoint = 2;
    for (var index = 1; index < saved.length; index++) {
      if (!puzzle.canExtend(
        saved[index - 1],
        saved[index],
        index,
        checkpoint,
        allowEarlyFinish: true,
      )) {
        return false;
      }
      if (puzzle.numbers[saved[index]] != 0) checkpoint++;
    }
    return true;
  }

  void restore(
    List<int> saved,
    List<List<int>> history,
    int hints,
    int? highlight,
  ) {
    if (!_validPath(saved)) return;
    _path = List.of(saved);
    _undo.clear();
    for (final previous in history.where(_validPath)) {
      if (previous.length < puzzle.area) _remember(List.of(previous));
    }
    hintsUsed = hints < 0 ? 0 : hints;
    if (highlight != null &&
        length < board.solution.length &&
        board.solution[length] == highlight &&
        _samePath(board.solution.take(length).toList(), _path)) {
      hintCell = highlight;
    }
  }

  List<List<int>> get history => [
    for (final previous in _undo) List<int>.of(previous),
    if (_beforeStroke case final before? when !_samePath(before, _path))
      List<int>.of(before),
  ];
}
