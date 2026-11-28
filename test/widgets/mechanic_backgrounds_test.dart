import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/logic/puzzle_generator.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/game_state.dart';
import 'package:pathwise/model/user_preferences.dart';
import 'package:pathwise/views/puzzle_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

void main() {
  const samples = {
    31: ['Walls'],
    71: ['Ice'],
    121: ['Keys and gates'],
    201: ['Portals'],
    306: ['Walls', 'Keys and gates', 'Portals', 'Ice'],
  };

  for (final (theme, window) in [
    (PathwiseTheme.field, const Size(320, 650)),
    (PathwiseTheme.blackwater, const Size(750, 950)),
  ]) {
    testWidgets(
      'mechanics and rule previews at $theme and ${window.width} dp',
      (tester) async {
        await tester.binding.setSurfaceSize(window);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final ads = AdService();
        for (final entry in samples.entries) {
          final id = PuzzleId.level(entry.key);
          final board = generatePuzzle(id.generation, level: id.level);
          final model = AppModel(
            snapshot: {
              'highestUnlocked': id.level,
              'mechanicTutorials': {
                'walls': 'completed',
                'ice': 'completed',
                'gate': 'completed',
                'portal': 'completed',
              },
            },
            storage: MemoryStorage(),
            loader: (_) async => board,
          )..setTheme(theme);
          await model.open(id);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: model),
                ChangeNotifierProvider.value(value: ads),
              ],
              child: MaterialApp(
                theme: BoardPalette.palettes[theme]!.theme,
                home: const PuzzleView(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final grid = find.byKey(const ValueKey('puzzle-grid'));
          expect(tester.getTopLeft(grid).dy, lessThan(300));
          final rules = find.widgetWithText(TextButton, 'Board rules');
          await tester.ensureVisible(rules);
          await tester.tap(rules);
          await tester.pumpAndSettle();
          for (final sample in entry.value) {
            expect(find.byKey(ValueKey('rule-sample-$sample')), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          model.dispose();
        }
        ads.dispose();
      },
    );
  }
}
