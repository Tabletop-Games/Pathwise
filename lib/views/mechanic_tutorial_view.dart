import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/game_controller.dart';
import '../logic/mechanic_tutorials.dart';
import '../logic/puzzle.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import 'components/puzzle_board.dart';

/// An isolated practice session: its controller never writes a player attempt.
class MechanicTutorialView extends StatefulWidget {
  const MechanicTutorialView({
    required this.mechanic,
    required this.onAcknowledge,
    super.key,
  });
  final MechanicTutorial mechanic;
  final Future<bool> Function(bool skipped) onAcknowledge;

  @override
  State<MechanicTutorialView> createState() => _MechanicTutorialViewState();
}

class _MechanicTutorialViewState extends State<MechanicTutorialView>
    implements BoardControls, RejectionControls {
  late GameController game;
  bool rejected = false;
  bool busy = false;

  Puzzle get board => game.puzzle;
  @override
  List<int> get path => game.path;
  @override
  int get tip => game.tip;
  @override
  int? get hintCell => null;
  @override
  int get nextCheckpoint => game.nextCheckpoint;
  @override
  bool get complete => game.complete;
  bool get success => switch (widget.mechanic) {
    MechanicTutorial.walls => rejected && path.contains(4),
    MechanicTutorial.gate => rejected && path.contains(3) && path.contains(1),
    MechanicTutorial.ice => path.contains(1) && path.contains(2),
    MechanicTutorial.portal => path.contains(1) && path.contains(8),
    MechanicTutorial.arrow => rejected && path.contains(3),
  };

  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    final puzzle = switch (widget.mechanic) {
      MechanicTutorial.walls => Puzzle(3, [0, 8], walls: [(0, 1)]),
      MechanicTutorial.ice => Puzzle(3, [0, 8], iceTiles: [1]),
      MechanicTutorial.gate => Puzzle(3, [0, 8], gate: (3, 1)),
      MechanicTutorial.portal => Puzzle(3, [0, 2], portal: (1, 8)),
      MechanicTutorial.arrow => Puzzle(3, [0, 8], arrow: (0, 3)),
    };
    game = GameController(VerifiedPuzzle(puzzle, const []));
    rejected = false;
  }

  @override
  bool canStep(int cell) => game.canStep(cell);
  @override
  bool begin(int cell) {
    final result = game.begin(cell);
    if (result) setState(() {});
    return result;
  }

  @override
  void step(int cell) {
    if (game.step(cell) != RouteEdit.none) setState(() {});
  }

  @override
  void end() {
    game.end();
  }

  @override
  void tap(int cell) {
    if (begin(cell)) end();
  }

  @override
  RejectedMove? rejectionFor(int cell) {
    final issue = game.rejectionFor(cell);
    final expected = switch (widget.mechanic) {
      MechanicTutorial.walls => MoveRejection.wall,
      MechanicTutorial.gate => MoveRejection.gate,
      MechanicTutorial.arrow => MoveRejection.arrow,
      _ => null,
    };
    if (expected != null && issue?.reason == expected && !rejected) {
      setState(() => rejected = true);
    }
    return issue;
  }

  @override
  void rejectHaptic() => context.read<AppModel>().haptic.error();

  Future<void> done(bool skipped) async {
    if (busy) return;
    setState(() => busy = true);
    final ok = await widget.onAcknowledge(skipped);
    if (!mounted) return;
    if (!ok) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.palettes[context.watch<AppModel>().theme]!;
    final (title, explanation, instruction) = switch (widget.mechanic) {
      MechanicTutorial.walls => (
        'Walls',
        'Walls block connections between tiles.',
        rejected
            ? 'Go around the wall through the tiles below.'
            : 'Try to cross the wall to the right.',
      ),
      MechanicTutorial.ice => (
        'Ice',
        'Ice carries the path straight ahead until a normal tile.',
        'Enter the ice tile to the right.',
      ),
      MechanicTutorial.gate => (
        'Keys and gates',
        'Collect the key before passing the locked gate.',
        rejected
            ? 'Collect the key below, then reach the gate.'
            : 'Try the locked gate to the right.',
      ),
      MechanicTutorial.portal => (
        'Portals',
        'Enter a solid portal to continue from its paired exit.',
        'Enter the portal to the right.',
      ),
      MechanicTutorial.arrow => (
        'Arrows',
        'Leave the arrow tile in the direction it points.',
        rejected
            ? 'Follow the arrow down.'
            : 'Try to move right, against the arrow.',
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('New mechanic'),
        actions: [
          TextButton(
            onPressed: busy ? null : () => done(true),
            child: const Text('Skip tutorial'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.min(
              (constraints.maxWidth - 32).clamp(0.0, 390.0),
              390.0,
            );
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'NEW MECHANIC',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(explanation),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox.square(
                    dimension: side,
                    child: PuzzleBoard(
                      model: this,
                      puzzle: board,
                      palette: palette,
                      tipStyle: context.watch<AppModel>().equippedTip,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    success ? 'Well done!' : instruction,
                    textAlign: TextAlign.center,
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => setState(reset),
                    child: const Text('Restart demo'),
                  ),
                ),
                FilledButton(
                  onPressed: success && !busy ? () => done(false) : null,
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
