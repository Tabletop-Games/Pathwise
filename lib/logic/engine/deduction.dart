import 'dart:typed_data';

import '../puzzle.dart';

/// Stable technique identifiers and the tier of reasoning each needs.
///
/// Tier 1 is local propagation a player does without lookahead. Tier 2 assumes
/// one edge and follows the consequences until a rule is broken. Tier 3 needs
/// a counting argument or a second assumption inside the first.
const techniqueTiers = <String, int>{
  'portal_link': 1,
  'forced_degree': 1,
  'saturated_cell': 1,
  'ice_straight': 1,
  'no_loop': 1,
  'order_merge': 1,
  'probe_dead_end': 2,
  'probe_order': 2,
  'probe_isolation': 2,
  'probe_budget': 3,
  'probe_deep': 3,
};

/// Plain-language reasons, suitable for explanatory hints.
const techniqueText = <String, String>{
  'portal_link': 'The two portal cells are always joined by the route.',
  'forced_degree': 'This cell has no other exit, so the route must use both of its open sides.',
  'saturated_cell': 'The route already enters and leaves this cell, so it cannot use any other side.',
  'ice_straight': 'Ice must be crossed in a straight line.',
  'no_loop': 'Joining these two ends of the same route would close a loop.',
  'order_merge':
      'Joining these two pieces of route would put the numbers out of order.',
  'probe_dead_end':
      'Trying this move forces a chain of moves that strands a cell.',
  'probe_order':
      'Trying this move forces the numbers or the key and gate out of order.',
  'probe_isolation':
      'Trying this move cuts the board into pieces the route cannot all visit.',
  'probe_budget': 'Trying this move leaves too few cells to reach the checkpoints in order.',
  'probe_deep': 'Trying this move leads, after two steps of reasoning, to a contradiction.',
};

/// One logical step: an edge between two cells is decided.
final class Deduction {
  const Deduction({
    required this.technique,
    required this.from,
    required this.to,
    required this.inRoute,
    required this.cell,
    required this.depth,
  });

  final String technique;

  /// The edge between [from] and [to]. Portal pairs count as an edge.
  final int from;
  final int to;

  /// True when the route uses the edge, false when it cannot.
  final bool inRoute;

  /// The cell whose constraint produced the step, or -1 for a probe.
  final int cell;

  /// How many dependent deductions, counting this one, lead to it.
  final int depth;

  int get tier => techniqueTiers[technique] ?? 3;
  String get explanation => techniqueText[technique] ?? technique;
}

/// The outcome of solving a board with logic alone.
final class DeductionResult {
  const DeductionResult({
    required this.solved,
    required this.inconsistent,
    required this.steps,
    required this.techniques,
    required this.hardestTier,
    required this.rounds,
    required this.depth,
    required this.unknownEdges,
    required this.path,
  });

  /// Every edge was decided by sound deductions of at most the allowed tier.
  final bool solved;

  /// A contradiction was reached from the board itself, so it has no solution.
  final bool inconsistent;
  final List<Deduction> steps;
  final Map<String, int> techniques;
  final int hardestTier;
  final int rounds;

  /// The length of the longest chain of deductions that each needed the one
  /// before it.
  final int depth;

  /// Edges still undecided when the solver ran out of techniques.
  final List<(int, int)> unknownEdges;

  /// The route found, when [solved].
  final List<int>? path;

  int get deductionCount => techniques.values.fold(0, (a, b) => a + b);
}

class _Step {
  _Step(this.technique, this.edge, this.value, this.cell, [this.pass = 0]);
  final String technique;
  final int edge;
  final int value;
  final int cell;

  /// The propagation layer that produced the step, counted from one.
  final int pass;
}

class _Topology {
  _Topology(this.puzzle) : area = puzzle.area {
    incident = List.generate(area, (_) => <int>[]);
    for (var cell = 0; cell < area; cell++) {
      for (final next in puzzle.movesFrom(cell)) {
        if (next < cell || puzzle.isWalled(cell, next)) continue;
        final id = eu.length;
        eu.add(cell);
        ev.add(next);
        incident[cell].add(id);
        incident[next].add(id);
        index[cell * 64 + next] = id;
        index[next * 64 + cell] = id;
      }
    }
    need = List.generate(
      area,
      (cell) => cell == puzzle.start || cell == puzzle.finish ? 1 : 2,
    );
    final size = puzzle.size;
    for (final cell in puzzle.iceTiles) {
      iceCells.add(cell);
      int edgeTo(int next) => index[cell * 64 + next] ?? -1;
      final column = cell % size;
      final row = cell ~/ size;
      iceEdges[cell] = [
        column > 0 ? edgeTo(cell - 1) : -1,
        column + 1 < size ? edgeTo(cell + 1) : -1,
        row > 0 ? edgeTo(cell - size) : -1,
        row + 1 < size ? edgeTo(cell + size) : -1,
      ];
    }
    final link = puzzle.portal;
    if (link != null) portalEdge = index[link.$1 * 64 + link.$2];
  }

  final Puzzle puzzle;
  final int area;
  final List<int> eu = [];
  final List<int> ev = [];
  late final List<List<int>> incident;
  late final List<int> need;
  final Map<int, int> index = {};
  final List<int> iceCells = [];
  final Map<int, List<int>> iceEdges = {};
  int? portalEdge;
  int get edgeCount => eu.length;
  int other(int edge, int cell) => eu[edge] == cell ? ev[edge] : eu[edge];
}

class _State {
  _State(this.t)
    : edge = Uint8List(t.edgeCount),
      inDeg = Uint8List(t.area),
      unkDeg = Uint8List(t.area),
      unknown = t.edgeCount {
    for (var cell = 0; cell < t.area; cell++) {
      unkDeg[cell] = t.incident[cell].length;
    }
  }

  final _Topology t;
  final Uint8List edge;
  final Uint8List inDeg;
  final Uint8List unkDeg;
  int unknown;

  void copyFrom(_State other) {
    edge.setAll(0, other.edge);
    inDeg.setAll(0, other.inDeg);
    unkDeg.setAll(0, other.unkDeg);
    unknown = other.unknown;
  }

  /// Decides an edge: 1 for in the route, 2 for not. False on a conflict.
  bool assign(int e, int value) {
    final current = edge[e];
    if (current == value) return true;
    if (current != 0) return false;
    edge[e] = value;
    unknown--;
    final a = t.eu[e];
    final b = t.ev[e];
    unkDeg[a]--;
    unkDeg[b]--;
    if (value == 1) {
      inDeg[a]++;
      inDeg[b]++;
    }
    return true;
  }
}

class _Hit {
  _Hit(this.edge, this.value, this.kind);
  final int edge;
  final int value;
  final String kind;
}

/// Sound constraint propagation and bounded lookahead on the route's edges.
class _Engine {
  _Engine(this.puzzle) : t = _Topology(puzzle) {
    final n = puzzle.area;
    fragOf = Int16List(n);
    order = Int16List(n);
    fragStart = Int16List(n + 1);
    disc = Int16List(n);
    low = Int16List(n);
    last = Int16List(n);
    parent = Int16List(n);
    separating = Int16List(n);
    cursor = Int16List(n);
    probe = _State(t);
    deepWork = _State(t);
    deepProbe = _State(t);
    work = _State(t);
    marked = Int8List(t.edgeCount);
  }

  final Puzzle puzzle;
  final _Topology t;
  late final Int16List fragOf;
  late final Int16List order;
  late final Int16List fragStart;
  late final Int16List disc;
  late final Int16List low;
  late final Int16List last;
  late final Int16List parent;
  late final Int16List separating;
  late final Int16List cursor;
  final List<int> _stack = [];
  late final _State probe;
  late final _State work;
  late final _State deepWork;
  late final _State deepProbe;
  late final Int8List marked;
  final List<int> _pendingEdge = [];
  final List<int> _pendingValue = [];
  final List<String> _pendingTech = [];
  final List<int> _pendingCell = [];
  int lastPasses = 0;
  int fragCount = 0;
  int _clock = 0;
  int propagations = 0;

  // Merge-check scratch.
  int _lastNumber = 0;
  int _direction = 0;
  bool _hasStart = false;
  bool _hasFinish = false;

  String? _buildFragments(_State s) {
    final n = t.area;
    for (var i = 0; i < n; i++) {
      fragOf[i] = -1;
    }
    var pos = 0;
    var count = 0;
    for (var cell = 0; cell < n; cell++) {
      if (fragOf[cell] != -1 || s.inDeg[cell] > 1) continue;
      fragStart[count] = pos;
      var prev = -1;
      var cur = cell;
      while (true) {
        fragOf[cur] = count;
        order[pos++] = cur;
        var next = -1;
        for (final e in t.incident[cur]) {
          if (s.edge[e] != 1) continue;
          final o = t.other(e, cur);
          if (o != prev) {
            next = o;
            break;
          }
        }
        if (next == -1) break;
        prev = cur;
        cur = next;
      }
      count++;
    }
    fragStart[count] = pos;
    fragCount = count;
    return pos == n ? null : 'dead_end';
  }

  String? _checkOrder() {
    final numbers = puzzle.numbers;
    final total = puzzle.checkpoints.length;
    final n = t.area;
    for (var f = 0; f < fragCount; f++) {
      final a = fragStart[f];
      final b = fragStart[f + 1];
      var previous = 0;
      var direction = 0;
      var hasStart = false;
      var hasFinish = false;
      for (var i = a; i < b; i++) {
        final number = numbers[order[i]];
        if (number == 0) continue;
        if (number == 1) hasStart = true;
        if (number == total) hasFinish = true;
        if (previous != 0) {
          final step = number - previous;
          if (step != 1 && step != -1) return 'order';
          if (direction == 0) {
            direction = step;
          } else if (direction != step) {
            return 'order';
          }
        }
        previous = number;
      }
      if (hasStart && hasFinish && b - a != n) return 'order';
    }
    return null;
  }

  bool _feed(int cell) {
    final number = puzzle.numbers[cell];
    if (number == 0) return true;
    if (number == 1) _hasStart = true;
    if (number == puzzle.checkpoints.length) _hasFinish = true;
    if (_lastNumber != 0) {
      final step = number - _lastNumber;
      if (step != 1 && step != -1) return false;
      if (_direction == 0) {
        _direction = step;
      } else if (_direction != step) {
        return false;
      }
    }
    _lastNumber = number;
    return true;
  }

  /// True when joining the end [u] of fragment [fu] to the end [v] of
  /// fragment [fv] keeps the checkpoint numbers in a legal order.
  bool _mergeOk(int fu, int u, int fv, int v) {
    _lastNumber = 0;
    _direction = 0;
    _hasStart = false;
    _hasFinish = false;
    final a0 = fragStart[fu];
    final a1 = fragStart[fu + 1];
    final b0 = fragStart[fv];
    final b1 = fragStart[fv + 1];
    if (order[a1 - 1] == u) {
      for (var i = a0; i < a1; i++) {
        if (!_feed(order[i])) return false;
      }
    } else {
      for (var i = a1 - 1; i >= a0; i--) {
        if (!_feed(order[i])) return false;
      }
    }
    if (order[b0] == v) {
      for (var i = b0; i < b1; i++) {
        if (!_feed(order[i])) return false;
      }
    } else {
      for (var i = b1 - 1; i >= b0; i--) {
        if (!_feed(order[i])) return false;
      }
    }
    if (_hasStart && _hasFinish && (a1 - a0) + (b1 - b0) != t.area) {
      return false;
    }
    return true;
  }

  bool _isEnd(int fragment, int cell) =>
      order[fragStart[fragment]] == cell ||
      order[fragStart[fragment + 1] - 1] == cell;

  void _clearPending() {
    for (final e in _pendingEdge) {
      marked[e] = 0;
    }
    _pendingEdge.clear();
    _pendingValue.clear();
    _pendingTech.clear();
    _pendingCell.clear();
  }

  /// Records a decision for the end of the pass. False when another rule in
  /// the same pass decided the same edge the other way.
  bool _queue(int e, int value, String technique, int cell) {
    final current = marked[e];
    if (current == value) return true;
    if (current != 0) return false;
    marked[e] = value;
    _pendingEdge.add(e);
    _pendingValue.add(value);
    _pendingTech.add(technique);
    _pendingCell.add(cell);
    return true;
  }

  /// Applies every tier-1 rule until nothing changes. Each pass reads a
  /// frozen copy of the board and applies its decisions together, so the
  /// number of passes is the depth of the longest chain of dependent
  /// deductions. Returns the kind of contradiction reached, or null.
  String? propagate(_State s, List<_Step>? log) {
    propagations++;
    _clearPending();
    var pass = 0;
    while (true) {
      pass++;
      if (pass > 400) return 'dead_end';
      for (var cell = 0; cell < t.area; cell++) {
        final need = t.need[cell];
        final inDeg = s.inDeg[cell];
        final unk = s.unkDeg[cell];
        if (inDeg > need || inDeg + unk < need) return 'dead_end';
        if (unk == 0) continue;
        final saturated = inDeg == need;
        if (!saturated && inDeg + unk != need) continue;
        final value = saturated ? 2 : 1;
        final technique = saturated ? 'saturated_cell' : 'forced_degree';
        for (final e in t.incident[cell]) {
          if (s.edge[e] != 0) continue;
          if (!_queue(e, value, technique, cell)) return 'dead_end';
        }
      }
      for (final cell in t.iceCells) {
        final sides = t.iceEdges[cell]!;
        bool open(int a, int b) =>
            a != -1 && b != -1 && s.edge[a] != 2 && s.edge[b] != 2;
        bool anyIn(int a, int b) =>
            (a != -1 && s.edge[a] == 1) || (b != -1 && s.edge[b] == 1);
        final horizontal =
            open(sides[0], sides[1]) && !anyIn(sides[2], sides[3]);
        final vertical = open(sides[2], sides[3]) && !anyIn(sides[0], sides[1]);
        if (!horizontal && !vertical) return 'dead_end';
        if (horizontal == vertical) continue;
        final keep = horizontal ? [sides[0], sides[1]] : [sides[2], sides[3]];
        final drop = horizontal ? [sides[2], sides[3]] : [sides[0], sides[1]];
        for (final e in keep) {
          if (e == -1 || s.edge[e] != 0) continue;
          if (!_queue(e, 1, 'ice_straight', cell)) return 'dead_end';
        }
        for (final e in drop) {
          if (e == -1 || s.edge[e] != 0) continue;
          if (!_queue(e, 2, 'ice_straight', cell)) return 'dead_end';
        }
      }
      var broken = _buildFragments(s);
      if (broken != null) return broken;
      broken = _checkOrder();
      if (broken != null) return broken;
      for (var e = 0; e < t.edgeCount; e++) {
        if (s.edge[e] != 0) continue;
        final u = t.eu[e];
        final v = t.ev[e];
        final fu = fragOf[u];
        final fv = fragOf[v];
        if (fu == fv) {
          if (!_queue(e, 2, 'no_loop', -1)) return 'dead_end';
        } else if (_isEnd(fu, u) && _isEnd(fv, v) && !_mergeOk(fu, u, fv, v)) {
          if (!_queue(e, 2, 'order_merge', -1)) return 'dead_end';
        }
      }
      if (_pendingEdge.isEmpty) break;
      for (var i = 0; i < _pendingEdge.length; i++) {
        final e = _pendingEdge[i];
        marked[e] = 0;
        if (!s.assign(e, _pendingValue[i])) {
          _clearPending();
          return 'dead_end';
        }
        log?.add(
          _Step(_pendingTech[i], e, _pendingValue[i], _pendingCell[i], pass),
        );
      }
      _pendingEdge.clear();
      _pendingValue.clear();
      _pendingTech.clear();
      _pendingCell.clear();
    }
    lastPasses = pass - 1;
    return null;
  }

  /// Contradictions that need more than local propagation.
  String? detect(_State s, {required bool counting}) {
    final broken = _buildFragments(s);
    if (broken != null) return broken;
    final region = _region(s);
    if (region != null) return region;
    final gate = _gate(s);
    if (gate != null) return gate;
    if (counting) return _budget(s);
    return null;
  }

  String? _region(_State s) {
    final n = t.area;
    for (var i = 0; i < n; i++) {
      disc[i] = 0;
      parent[i] = -1;
      separating[i] = 0;
    }
    _clock = 0;
    if (_visit(s, 0) != n) return 'isolation';
    for (var c = 1; c < n; c++) {
      final up = parent[c];
      if (up == 0 || low[c] >= disc[up]) separating[up]++;
    }
    final start = puzzle.start;
    final finish = puzzle.finish;
    for (var v = 0; v < n; v++) {
      final cut = separating[v];
      if (cut == 0) continue;
      final components = v == 0 ? cut : cut + 1;
      if (components < 2) continue;
      if (v == start || v == finish || components > 2) return 'isolation';
      var startSide = -1;
      var finishSide = -1;
      for (var c = 1; c < n; c++) {
        if (parent[c] != v || !(v == 0 || low[c] >= disc[v])) continue;
        if (disc[c] <= disc[start] && disc[start] <= last[c]) startSide = c;
        if (disc[c] <= disc[finish] && disc[finish] <= last[c]) finishSide = c;
      }
      if (startSide == finishSide) return 'isolation';
    }
    return null;
  }

  /// Iterative Tarjan low-link over the edges that are not ruled out. Returns
  /// how many cells were reached.
  int _visit(_State s, int root) {
    final stack = _stack..clear();
    stack.add(root);
    for (var i = 0; i < t.area; i++) {
      cursor[i] = 0;
    }
    disc[root] = ++_clock;
    low[root] = disc[root];
    last[root] = disc[root];
    var count = 1;
    while (stack.isNotEmpty) {
      final cell = stack.last;
      final edges = t.incident[cell];
      if (cursor[cell] < edges.length) {
        final e = edges[cursor[cell]++];
        if (s.edge[e] == 2) continue;
        final next = t.other(e, cell);
        if (disc[next] == 0) {
          parent[next] = cell;
          disc[next] = ++_clock;
          low[next] = disc[next];
          last[next] = disc[next];
          stack.add(next);
          count++;
        } else if (next != parent[cell] && disc[next] < low[cell]) {
          low[cell] = disc[next];
        }
      } else {
        stack.removeLast();
        final up = parent[cell];
        if (up >= 0) {
          if (low[cell] < low[up]) low[up] = low[cell];
          if (last[cell] > last[up]) last[up] = last[cell];
        }
      }
    }
    return count;
  }

  String? _gate(_State s) {
    final gate = puzzle.gate;
    if (gate == null) return null;
    final key = gate.$1;
    final door = gate.$2;
    final start = puzzle.start;
    final finish = puzzle.finish;
    final fk = fragOf[key];
    final fg = fragOf[door];
    if (fk != fg) {
      if (fragOf[start] == fg) return 'order';
      if (fragOf[finish] == fk) return 'order';
      return null;
    }
    final a = fragStart[fk];
    final b = fragStart[fk + 1];
    var direction = 0;
    if (fragOf[start] == fk) {
      direction = order[a] == start ? 1 : -1;
    } else if (fragOf[finish] == fk) {
      direction = order[b - 1] == finish ? 1 : -1;
    } else {
      var previous = 0;
      for (var i = a; i < b && direction == 0; i++) {
        final number = puzzle.numbers[order[i]];
        if (number == 0) continue;
        if (previous != 0) direction = number > previous ? 1 : -1;
        previous = number;
      }
    }
    if (direction == 0) return null;
    var keyAt = -1;
    var doorAt = -1;
    for (var i = a; i < b; i++) {
      if (order[i] == key) keyAt = i;
      if (order[i] == door) doorAt = i;
    }
    return (keyAt - doorAt) * direction < 0 ? null : 'order';
  }

  String? _budget(_State s) {
    final cells = puzzle.checkpoints;
    var needed = 0;
    final distance = List<int>.filled(t.area, -1);
    final queue = <int>[];
    for (var i = 0; i < cells.length - 1; i++) {
      for (var c = 0; c < t.area; c++) {
        distance[c] = -1;
      }
      queue
        ..clear()
        ..add(cells[i]);
      distance[cells[i]] = 0;
      for (var head = 0; head < queue.length; head++) {
        final cell = queue[head];
        if (cell == cells[i + 1]) break;
        for (final e in t.incident[cell]) {
          if (s.edge[e] == 2) continue;
          final next = t.other(e, cell);
          if (distance[next] != -1) continue;
          distance[next] = distance[cell] + 1;
          queue.add(next);
        }
      }
      final d = distance[cells[i + 1]];
      if (d < 0) return 'budget';
      needed += d;
    }
    return needed > t.area - 1 ? 'budget' : null;
  }

  /// Assumes the undecided edge [e] both ways on a copy of [s]. The
  /// assumption that breaks a rule decides the edge the other way.
  _Hit? probeEdge(
    _State s,
    _State scratch,
    int e, {
    required bool counting,
  }) {
    scratch.copyFrom(s);
    scratch.assign(e, 1);
    final ifIn = propagate(scratch, null) ?? detect(scratch, counting: counting);
    scratch.copyFrom(s);
    scratch.assign(e, 2);
    final ifOut =
        propagate(scratch, null) ?? detect(scratch, counting: counting);
    if (ifIn != null && ifOut != null) return _Hit(e, 0, 'inconsistent');
    if (ifIn != null) return _Hit(e, 2, ifIn);
    if (ifOut != null) return _Hit(e, 1, ifOut);
    return null;
  }

  /// The first edge, in order, that one assumption decides.
  _Hit? probeScan(_State s, _State scratch, {required bool counting}) {
    for (var e = 0; e < t.edgeCount; e++) {
      if (s.edge[e] != 0) continue;
      final hit = probeEdge(s, scratch, e, counting: counting);
      if (hit != null) return hit;
    }
    return null;
  }

  /// A second assumption inside the first. Bounded by [budget] propagations.
  _Hit? deepScan(_State s, int budget) {
    final stop = propagations + budget;
    for (var e = 0; e < t.edgeCount; e++) {
      if (s.edge[e] != 0) continue;
      for (final value in const [1, 2]) {
        if (propagations > stop) return null;
        deepWork.copyFrom(s);
        deepWork.assign(e, value);
        if (propagate(deepWork, null) != null) continue;
        var contradiction = false;
        while (propagations <= stop) {
          final inner = probeScan(deepWork, deepProbe, counting: false);
          if (inner == null) break;
          if (inner.value == 0 || !deepWork.assign(inner.edge, inner.value)) {
            contradiction = true;
            break;
          }
          if (propagate(deepWork, null) != null) {
            contradiction = true;
            break;
          }
          if (deepWork.unknown == 0) break;
        }
        if (contradiction) return _Hit(e, value == 1 ? 2 : 1, 'deep');
      }
    }
    return null;
  }
}

String _techniqueFor(String kind) => switch (kind) {
  'order' => 'probe_order',
  'isolation' => 'probe_isolation',
  'budget' => 'probe_budget',
  _ => 'probe_dead_end',
};

/// Solves [puzzle] with sound logical deductions only.
///
/// The certified solution is never consulted: every step is derived from the
/// clues, walls and mechanics. A board is [DeductionResult.solved] when logic
/// up to [maxTier] decides every edge. Otherwise [DeductionResult.unknownEdges]
/// lists what a player would still have to guess.
DeductionResult deduce(
  Puzzle puzzle, {
  int maxTier = 3,
  int deepBudget = 3000,
  bool trace = true,
}) {
  final engine = _Engine(puzzle);
  final t = engine.t;
  final state = _State(t);
  final raw = <_Step>[];
  final steps = <Deduction>[];
  final counts = <String, int>{};
  var hardest = 0;
  var rounds = 0;
  var depth = 0;
  var inconsistent = false;

  void emit(_Step step, int level) {
    final tier = techniqueTiers[step.technique] ?? 3;
    if (tier > hardest) hardest = tier;
    counts.update(step.technique, (n) => n + 1, ifAbsent: () => 1);
    if (trace) {
      steps.add(
        Deduction(
          technique: step.technique,
          from: t.eu[step.edge],
          to: t.ev[step.edge],
          inRoute: step.value == 1,
          cell: step.cell,
          depth: level,
        ),
      );
    }
  }

  final link = t.portalEdge;
  if (link != null) {
    state.assign(link, 1);
    emit(_Step('portal_link', link, 1, -1), 0);
  }

  // Applies a lookahead result, then the propagation it unlocks.
  bool applyHit(_Hit hit, String kind) {
    if (hit.value == 0 || !state.assign(hit.edge, hit.value)) return false;
    rounds++;
    depth++;
    emit(_Step(kind, hit.edge, hit.value, -1), depth);
    raw.clear();
    final broken = engine.propagate(state, raw);
    if (raw.isNotEmpty) {
      for (final step in raw) {
        emit(step, depth + step.pass);
      }
      depth += engine.lastPasses;
    }
    return broken == null;
  }

  // One sweep over the undecided edges. Every success is applied at once and
  // the sweep carries on, so a board with many lookahead deductions is not
  // rescanned from the start each time.
  bool sweep({required bool counting}) {
    var any = false;
    for (var e = 0; e < t.edgeCount; e++) {
      if (state.edge[e] != 0) continue;
      final hit = engine.probeEdge(state, engine.probe, e, counting: counting);
      if (hit == null) continue;
      if (!applyHit(hit, _techniqueFor(hit.kind))) {
        inconsistent = true;
        return true;
      }
      any = true;
      if (state.unknown == 0) break;
    }
    return any;
  }

  while (true) {
    raw.clear();
    final broken = engine.propagate(state, raw);
    if (raw.isNotEmpty) {
      rounds++;
      for (final step in raw) {
        emit(step, depth + step.pass);
      }
      depth += engine.lastPasses;
    }
    if (broken != null) {
      inconsistent = true;
      break;
    }
    if (state.unknown == 0 || maxTier < 2) break;
    if (sweep(counting: false)) {
      if (inconsistent) break;
      continue;
    }
    if (maxTier < 3) break;
    if (sweep(counting: true)) {
      if (inconsistent) break;
      continue;
    }
    final deep = engine.deepScan(state, deepBudget);
    if (deep == null) break;
    if (!applyHit(deep, 'probe_deep')) {
      inconsistent = true;
      break;
    }
  }

  List<int>? path;
  var solved = !inconsistent && state.unknown == 0;
  if (solved) {
    path = _extract(puzzle, t, state);
    if (path == null) {
      solved = false;
      inconsistent = true;
    }
  }
  return DeductionResult(
    solved: solved,
    inconsistent: inconsistent,
    steps: List.unmodifiable(steps),
    techniques: Map.unmodifiable(counts),
    hardestTier: hardest,
    rounds: rounds,
    depth: depth,
    unknownEdges: [
      for (var e = 0; e < t.edgeCount; e++)
        if (state.edge[e] == 0) (t.eu[e], t.ev[e]),
    ],
    path: path,
  );
}

List<int>? _extract(Puzzle puzzle, _Topology t, _State s) {
  final route = [puzzle.start];
  var previous = -1;
  var cell = puzzle.start;
  while (route.length < puzzle.area) {
    var next = -1;
    for (final e in t.incident[cell]) {
      if (s.edge[e] != 1) continue;
      final other = t.other(e, cell);
      if (other != previous) {
        next = other;
        break;
      }
    }
    if (next == -1) return null;
    final visited = route.toSet();
    if (visited.contains(next)) return null;
    final checkpoint = 1 + route.where((c) => puzzle.numbers[c] != 0).length;
    if (puzzle.rejectionFor(
          cell,
          next,
          route.length,
          checkpoint,
          previous: route.length > 1 ? route[route.length - 2] : null,
          hasVisited: visited.contains,
        ) !=
        null) {
      return null;
    }
    route.add(next);
    previous = cell;
    cell = next;
  }
  return cell == puzzle.finish ? route : null;
}
