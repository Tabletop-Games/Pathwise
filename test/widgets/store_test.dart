import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/app_themes.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/path_tips.dart';
import '../../lib/model/user_preferences.dart';
import '../../lib/ui/game_ui.dart';
import '../../lib/views/components/puzzle_board.dart';
import '../../lib/views/components/tip_art.dart';
import '../../lib/views/store_view.dart';
import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalogue identifiers and independent initial prices are stable', () {
    expect(PathTip.values.length, 19);
    expect(PathTip.values.map((e) => e.name).toSet().length, 19);
    expect(PathTip.classic.price, 0);
    expect(
      PathTip.values
          .skip(1)
          .every((e) => {240, 500, 1000, 1800}.contains(e.price)),
      isTrue,
    );
    expect(PathTip.fromId('invalid'), isNull);
    expect(PathTip.fromId('arrow'), isNull);
  });

  test('invalid saved identifiers default safely to classic', () {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'ownedTips': ['unknown', 'crystal'],
        'equippedTip': 'unknown',
      },
    );
    expect(model.ownsTip(PathTip.classic), isTrue);
    expect(model.ownsTip(PathTip.crystal), isTrue);
    expect(model.equippedTip, PathTip.classic);
    model.dispose();
  });

  test(
    'tip purchase is a single durable debit and equip remains explicit',
    () async {
      final storage = MemoryStorage();
      final model = AppModel(
        storage: storage,
        snapshot: {
          'ledger': [
            {
              'id': 'starter',
              'label': 'Welcome',
              'amount': 320,
              'at': '2026-01-01T00:00:00Z',
            },
          ],
        },
      );
      final results = await Future.wait([
        model.buyTip(PathTip.crystal),
        model.buyTip(PathTip.crystal),
      ]);
      expect(results.where((x) => x).length, 1);
      expect(model.coinBalance, 80);
      expect(model.ownsTip(PathTip.crystal), isTrue);
      expect(model.equippedTip, PathTip.classic);
      expect(await model.equipTip(PathTip.crystal), isTrue);
      final saved = await storage.load();
      final restored = AppModel(storage: storage, snapshot: saved);
      expect(restored.coinBalance, 80);
      expect(restored.ownsTip(PathTip.crystal), isTrue);
      expect(restored.equippedTip, PathTip.crystal);
      model.dispose();
      restored.dispose();
    },
  );

  test(
    'insufficient balance and failed persistence do not issue duplicate debits',
    () async {
      final store = MemoryStorage();
      final model = AppModel(storage: store, snapshot: {});
      expect(await model.buyTip(PathTip.crystal), isFalse);
      expect(model.coinBalance, 50);
      expect(model.ownsTip(PathTip.crystal), isFalse);
      model.dispose();
      final rich = AppModel(
        storage: store,
        snapshot: {
          'ledger': [
            {
              'id': 'starter',
              'label': 'Welcome',
              'amount': 270,
              'at': '2026-01-01T00:00:00Z',
            },
          ],
        },
      );
      store.fail = true;
      expect(await rich.buyTip(PathTip.crystal), isFalse);
      expect(rich.storageError, isTrue);
      expect(await rich.buyTip(PathTip.crystal), isFalse);
      expect(rich.coinBalance, 30);
      store.fail = false;
      expect(await rich.flush(), isTrue);
      final restored = AppModel(storage: store, snapshot: await store.load());
      expect(restored.ownsTip(PathTip.crystal), isTrue);
      expect(restored.coinBalance, 30);
      rich.dispose();
      restored.dispose();
    },
  );

  for (final theme in [
    PathwiseTheme.field,
    PathwiseTheme.blackwater,
    PathwiseTheme.amoledCarbon,
    PathwiseTheme.signal,
  ]) {
    testWidgets('tip illustrations paint with ${theme.label} palette', (
      tester,
    ) async {
      final palette = BoardPalette.palettes[theme]!;
      await tester.pumpWidget(
        MaterialApp(
          theme: palette.theme,
          home: Scaffold(
            body: GridView.count(
              crossAxisCount: 4,
              children: [
                for (final tip in PathTip.values)
                  TipArtwork(tip: tip, palette: palette),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(GridView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Rocket path tip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(320, 700),
    const Size(390, 850),
    const Size(700, 900),
  ]) {
    testWidgets('store categories and original artwork fit $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(storage: MemoryStorage(), snapshot: {});
      final ads = AdService();
      final billing = BillingService(persist: (_) async => true);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            ChangeNotifierProvider.value(value: ads),
            ChangeNotifierProvider.value(value: billing),
          ],
          child: MaterialApp(
            theme: BoardPalette.palettes[PathwiseTheme.field]!.theme,
            home: const StoreView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Store'), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-card-field')), findsOneWidget);
      final grid = tester.widget<GridView>(
        find.byKey(const PageStorageKey('store-themes')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        size.width >= 560 ? 4 : 3,
      );
      await tester.tap(find.text('Tips'));
      await tester.pumpAndSettle();
      final tips = tester.widget<GridView>(
        find.byKey(const PageStorageKey('store-tips')),
      );
      expect(
        (tips.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        size.width >= 560 ? 4 : 3,
      );
      expect(find.byType(TipArtwork), findsWidgets);
      final card = find.byKey(const ValueKey('tip-card-crystal'));
      await tester.tap(
        find.descendant(of: card, matching: find.byType(TipArtwork)),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Up'), findsNothing);
      expect(find.byTooltip('Right'), findsNothing);
      expect(find.byTooltip('Down'), findsNothing);
      expect(find.byTooltip('Left'), findsNothing);
      expect(model.equippedTip, PathTip.classic);
      final preview = tester.widget<LevelOneBoardPreview>(
        find.descendant(
          of: find.byType(GameDialog),
          matching: find.byType(LevelOneBoardPreview),
        ),
      );
      expect(preview.tip, PathTip.crystal);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      ads.dispose();
      billing.dispose();
    });
  }

  testWidgets(
    'TipArtwork in Store omits circular contrast ring on signal/amoled',
    (tester) async {
      for (final theme in [PathwiseTheme.signal, PathwiseTheme.amoledCarbon]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TipArtwork(
                tip: PathTip.crystal,
                palette: BoardPalette.palettes[theme]!,
              ),
            ),
          ),
        );
        expect(find.byType(DecoratedBox), findsNothing);
      }
    },
  );
}
