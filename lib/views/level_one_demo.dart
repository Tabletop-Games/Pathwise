import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/game_controller.dart';
import '../logic/puzzle_generator.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_state.dart';
import 'components/puzzle_board.dart';

Future<void> openLevelOneDemo(BuildContext context) =>
    Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const _LevelOneDemo()));

class _LevelOneDemo extends StatefulWidget {
  const _LevelOneDemo();

  @override
  State<_LevelOneDemo> createState() => _LevelOneDemoState();
}

class _LevelOneDemoState extends State<_LevelOneDemo> implements BoardControls {
  static final _board = generatePuzzle(
    const PuzzleId.level(1).generation,
    level: 1,
  );
  GameController _game = GameController(_board);

  @override
  List<int> get path => _game.path;
  @override
  int get tip => _game.tip;
  @override
  int get nextCheckpoint => _game.nextCheckpoint;
  @override
  bool get complete => _game.complete;
  @override
  int? get hintCell => complete ? null : _board.solution[_game.length];

  @override
  bool canStep(int cell) => cell == hintCell && _game.canStep(cell);

  @override
  bool begin(int cell) {
    if ((!path.contains(cell) && !canStep(cell)) || !_game.begin(cell)) {
      return false;
    }
    setState(() {});
    return true;
  }

  @override
  void step(int cell) {
    final route = path;
    if ((canStep(cell) ||
            (route.length > 1 && cell == route[route.length - 2])) &&
        _game.step(cell) != RouteEdit.none) {
      setState(() {});
    }
  }

  @override
  void end() => _game.end();

  @override
  void tap(int cell) {
    if (begin(cell)) end();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.select((AppModel model) => model.theme);
    final palette = BoardPalette.palettes[theme]!;
    final started = _game.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Level 1 demo'),
        actions: [
          if (!complete)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.min(
              (constraints.maxWidth - 32).clamp(0.0, 420.0),
              (constraints.maxHeight * 0.68).clamp(160.0, 420.0),
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  complete ? 'Level 1 solved!' : 'Draw one continuous route',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  complete
                      ? 'You covered every tile and reached the last checkpoint.'
                      : 'Visit the numbers in order and cover every tile. You can drag back to undo a move.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox.square(
                    dimension: side,
                    child: PuzzleBoard(
                      model: this,
                      puzzle: _board.puzzle,
                      palette: palette,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (complete)
                  Center(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  )
                else ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      started
                          ? 'Keep following the highlighted tile.'
                          : 'Start at 1 and drag to the highlighted tile.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Center(
                    child: TextButton.icon(
                      onPressed: started
                          ? () => setState(() => _game = GameController(_board))
                          : null,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Restart demo'),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
