import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/user_preferences.dart';
import '../lib/views/components/puzzle_board.dart';
import '../lib/views/settings_view.dart';
import '../lib/views/themes_view.dart';
import 'app_model_test.dart' show MemoryStorage;

void main() {
  testWidgets('preview recolors the screen without equipping until Apply', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryStorage();
    final model = AppModel(
      storage: storage,
      snapshot: {
        'ownedThemes': ['blackwater'],
      },
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: model,
        child: const MaterialApp(home: ThemesView()),
      ),
    );
    final board = find.byType(LevelOneBoardPreview);
    final initialPosition = tester.getTopLeft(board);
    final row = find.byKey(const ValueKey('theme-row-blackwater'));
    await tester.ensureVisible(row);
    expect(tester.getTopLeft(board), initialPosition);
    final field = BoardPalette.palettes[PathwiseTheme.field]!.theme.colorScheme;
    Text title() => tester.widget<Text>(
      find.descendant(of: row, matching: find.text('Blackwater')),
    );
    expect(title().style!.color, field.onSurface);
    await tester.tap(find.text('Blackwater').last);
    await tester.pumpAndSettle();
    expect(model.theme, PathwiseTheme.field);
    final blackwater =
        BoardPalette.palettes[PathwiseTheme.blackwater]!.theme.colorScheme;
    expect(title().style!.color, blackwater.onSurface);
    expect(tester.getTopLeft(board), initialPosition);
    expect(tester.widget<ListTile>(row).selected, isTrue);
    final apply = find.descendant(of: row, matching: find.text('Apply'));
    final ink = tester.widget<Ink>(
      find.ancestor(of: apply, matching: find.byType(Ink)).first,
    );
    expect((ink.decoration as ShapeDecoration).color, blackwater.secondary);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(model.theme, PathwiseTheme.blackwater);
    expect(title().style!.color, blackwater.onSurface);
    expect(
      find.descendant(of: row, matching: find.text('Equipped')),
      findsOneWidget,
    );
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LevelOneBoardPreview>(find.byType(LevelOneBoardPreview))
          .palette,
      same(BoardPalette.palettes[PathwiseTheme.blackwater]),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
    final restored = AppModel(storage: storage, snapshot: await storage.load());
    expect(restored.theme, PathwiseTheme.blackwater);
    restored.dispose();
  });

  testWidgets(
    'Settings omits reward information and retains management entries',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final model = AppModel(storage: MemoryStorage(), snapshot: {});
      final ads = AdService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            ChangeNotifierProvider.value(value: ads),
          ],
          child: const MaterialApp(home: SettingsView()),
        ),
      );
      expect(find.text('Reward information'), findsNothing);
      expect(find.text('Haptic feedback'), findsOneWidget);
      expect(find.text('Google Play Achievements'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('Ad privacy'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
      ads.dispose();
    },
  );
}
