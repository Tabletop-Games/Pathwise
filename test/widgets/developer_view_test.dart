import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/economy.dart';
import 'package:pathwise/model/progression.dart';
import 'package:pathwise/model/user_preferences.dart';
import 'package:pathwise/views/developer_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

AppModel _model({required bool debugTools}) => AppModel(
  storage: MemoryStorage(),
  snapshot: {},
  today: () => DateTime(2026, 11, 23),
  debugTools: debugTools,
);

Future<void> _open(WidgetTester tester, AppModel model) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<AppModel>.value(
      value: model,
      child: MaterialApp(
        theme: BoardPalette.palettes[PathwiseTheme.field]!.theme,
        home: const DeveloperView(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _status(WidgetTester tester) {
  final finder = find.byType(SelectableText);
  return finder.evaluate().isEmpty
      ? null
      : tester.widget<SelectableText>(finder).data;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('model gating', () {
    test('every mutation is ignored unless developer tools are enabled', () {
      final model = _model(debugTools: false);
      final coins = model.coinBalance;
      final day = model.todayKey;
      expect(model.developerMode, isFalse);
      model.setDebugResources(coins: 99999, hints: 99);
      model.advanceDebugDay(qualify: true);
      model.grantDebugProgression();
      expect(model.coinBalance, coins);
      expect(model.todayKey, day);
      expect(model.streak.count, 0);
      expect(model.progression.rank(Research.magnet), 0);
      model.dispose();
    });

    test('enabled tools set resources exactly and ignore invalid values', () {
      final model = _model(debugTools: true);
      expect(model.developerMode, isTrue);
      model.setDebugResources(coins: 777, hints: 12);
      expect(model.coinBalance, 777);
      expect(model.hintsRemaining, 12);
      model.setDebugResources(coins: -5, hints: -1);
      expect(model.coinBalance, 777);
      expect(model.hintsRemaining, 12);
      model.setDebugResources(coins: 0);
      expect(model.coinBalance, 0);
      model.dispose();
    });

    test('a simulated day advances the clock and can qualify the streak', () {
      final model = _model(debugTools: true);
      expect(model.todayKey, '2026-11-23');
      model.advanceDebugDay(qualify: true);
      expect(model.todayKey, '2026-11-24');
      expect(model.streak.count, 1);
      model.advanceDebugDay();
      expect(model.todayKey, '2026-11-25');
      model.dispose();
    });

    test(
      'granting progression maxes research and fills boosts and freezes',
      () {
        final model = _model(debugTools: true);
        model.grantDebugProgression();
        for (final item in Research.values) {
          expect(model.progression.rank(item), item.limit);
        }
        for (final boost in Boost.values) {
          expect(model.progression.inventory[boost.name], 1);
        }
        expect(model.streak.freezes, economy.maxFreezes);
        model.dispose();
      },
    );
  });

  testWidgets('DeveloperView hides all tools when developerMode is false', (
    tester,
  ) async {
    final model = _model(debugTools: false);
    await _open(tester, model);
    expect(find.text('Developer dashboard'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('the dashboard sets coins and hints from its fields', (
    tester,
  ) async {
    final model = _model(debugTools: true);
    await _open(tester, model);
    expect(find.text('Developer dashboard'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Coins'), '777');
    await _tap(tester, 'Set coins');
    expect(model.coinBalance, 777);
    expect(_status(tester), 'Coins set to 777.');
    await tester.enterText(find.widgetWithText(TextField, 'Hints'), '9');
    await _tap(tester, 'Set hints');
    expect(model.hintsRemaining, 9);
    await tester.enterText(find.widgetWithText(TextField, 'Coins'), 'many');
    await _tap(tester, 'Set coins');
    expect(model.coinBalance, 777);
    expect(_status(tester), 'Enter a valid coin amount (>= 0).');
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('the dashboard simulates days and unlocks progression', (
    tester,
  ) async {
    final model = _model(debugTools: true);
    await _open(tester, model);
    await _tap(tester, 'Simulate qualifying day');
    expect(model.streak.count, 1);
    await _tap(tester, 'Skip to next day');
    expect(model.todayKey, '2026-11-25');
    await _tap(tester, 'Unlock Research & grant Boosts / Freezes');
    expect(model.progression.rank(Research.magnet), Research.magnet.limit);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });
}
