import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/game_controller.dart';
import '../logic/mechanic_tutorials.dart';
import '../logic/puzzle.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../ui/game_ui.dart';
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
    MechanicTutorial.walls => complete || (rejected && path.contains(4)),
    MechanicTutorial.gate =>
      complete || (rejected && path.contains(3) && path.contains(1)),
    MechanicTutorial.ice => complete || (path.contains(1) && path.contains(2)),
    MechanicTutorial.portal =>
      complete || (path.contains(1) && path.contains(8)),
    MechanicTutorial.arrow => complete || (rejected && path.contains(3)),
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
    var ok = false;
    try {
      ok = await widget.onAcknowledge(skipped);
    } finally {
      if (mounted && !ok) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save tutorial progress. Please try again.',
            ),
          ),
        );
      }
    }
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
          ActionPill(
            label: 'Skip tutorial',
            onTap: busy ? null : () => done(true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AtmosphericBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxBoard = math.min(
                (constraints.maxWidth - 32).clamp(0.0, 360.0),
                (constraints.maxHeight - 230).clamp(180.0, 360.0),
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        explanation,
                        style: TextStyle(color: palette.mutedInk),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: SizedBox.square(
                      dimension: maxBoard,
                      child: PuzzleBoard(
                        model: this,
                        puzzle: board,
                        palette: palette,
                        tipStyle: context.watch<AppModel>().equippedTip,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      success ? 'Well done!' : instruction,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: success ? palette.route : palette.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ActionPill(
                        label: 'Restart demo',
                        icon: Icons.restart_alt_rounded,
                        onTap: busy ? null : () => setState(reset),
                      ),
                      ActionPill(
                        label: busy ? 'Saving…' : 'Continue',
                        tone: ActionTone.primary,
                        onTap: success && !busy ? () => done(false) : null,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
