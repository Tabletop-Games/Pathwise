import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/game_controller.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/user_preferences.dart';
import 'package:pathwise/views/components/puzzle_board.dart';

void main() {
  test('preview selection text remains readable across all palettes', () {
    for (final theme in PathwiseTheme.values) {
      final scheme = BoardPalette.palettes[theme]!.theme.colorScheme;
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
      }

      expect(
        contrast(scheme.onSurface, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
        reason: theme.label,
      );
      expect(
        contrast(scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} equipped',
      );
    }
  });

  test('preview is an isolated valid partial Level 1 route', () {
    final board = LevelOneBoardPreview.board;
    final route = LevelOneBoardPreview.previewRoute;
    expect(route, board.solution.take(route.length).toList());
    expect(route.length / board.solution.length, inInclusiveRange(.4, .6));
    expect(board.puzzle.numbers[route.last], 0);
    expect(
      route.where((cell) => board.puzzle.numbers[cell] > 0).length,
      greaterThan(1),
    );
    expect(
      board.puzzle.checkpoints.where((cell) => !route.contains(cell)),
      isNotEmpty,
    );
    final game = GameController(board);
    expect(game.begin(route.first), isTrue);
    for (final cell in route.skip(1)) {
      expect(game.step(cell), RouteEdit.advance);
    }
    expect(game.path, route);
    expect(game.complete, isFalse);
  });
}
