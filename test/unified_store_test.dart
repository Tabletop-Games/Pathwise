import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/puzzle.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/path_tips.dart';
import '../lib/model/user_preferences.dart';
import '../lib/views/components/puzzle_board.dart';
import '../lib/views/components/tip_art.dart';
import '../lib/views/store_view.dart';
import 'app_model_test.dart' show MemoryStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalogue identifiers and independent initial prices are stable', () {
    expect(PathTip.values.length, 20);
    expect(PathTip.values.map((e) => e.name).toSet().length, 20);
    expect(PathTip.classic.price, 0);
    expect(PathTip.values.skip(1).every((e) => e.price == 100), isTrue);
    expect(PathTip.fromId('invalid'), isNull);
  });

  test('direction follows accepted route, skipping portal transport', () {
    final board = Puzzle(4, [0, 15], portal: (5, 10));
    expect(tipDirection(board, [0]), 0);
    expect(tipDirection(board, [0, 1]), 0);
    expect(tipDirection(board, [0, 4]), 1);
    expect(tipDirection(board, [0, 1, 0]), 2);
    expect(tipDirection(board, [0, 4, 0]), 3);
    expect(tipDirection(board, [0, 1, 5, 10]), 1);
    expect(tipDirection(board, [0, 1, 5, 10, 11]), 0);
    expect(tipDirection(board, [0, 1, 5]), 1);
    final adjacentPortal = Puzzle(4, [0, 15], portal: (1, 2));
    expect(tipDirection(adjacentPortal, [0, 4, 5, 1, 2]), 3);
  });

  test('old saves and invalid identifiers default safely to classic', () {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'ownedTips': ['unknown', 'arrow'],
        'equippedTip': 'unknown',
      },
    );
    expect(model.ownsTip(PathTip.classic), isTrue);
    expect(model.ownsTip(PathTip.arrow), isTrue);
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
              'amount': 200,
              'at': '2026-01-01T00:00:00Z',
            },
          ],
        },
      );
      final results = await Future.wait([
        model.buyTip(PathTip.arrow),
        model.buyTip(PathTip.arrow),
      ]);
      expect(results.where((x) => x).length, 1);
      expect(model.coinBalance, 100);
      expect(model.ownsTip(PathTip.arrow), isTrue);
      expect(model.equippedTip, PathTip.classic);
      expect(await model.equipTip(PathTip.arrow), isTrue);
      final saved = await storage.load();
      final restored = AppModel(storage: storage, snapshot: saved);
      expect(restored.coinBalance, 100);
      expect(restored.ownsTip(PathTip.arrow), isTrue);
      expect(restored.equippedTip, PathTip.arrow);
      model.dispose();
      restored.dispose();
    },
  );

  test(
    'coin offers require both five new levels and fifteen minutes',
    () async {
      var now = 899999;
      final store = MemoryStorage();
      Map<String, dynamic> snapshot(int solved, {bool adFree = false}) => {
        'coinOffer': {'levels': 2, 'boot': 1, 'milliseconds': 0},
        'results': {
          for (var i = 1; i <= solved; i++)
            'levels/$i': {'milliseconds': 1000, 'hints': 0},
        },
        'removeAds': adFree,
      };
      final model = AppModel(
        storage: store,
        snapshot: snapshot(7),
        bootTime: () => (boot: 1, milliseconds: now),
      );
      expect(model.canOfferCoinVideo, isFalse);
      now = 900000;
      expect(model.canOfferCoinVideo, isTrue);
      expect(await model.recordCoinOffer(), isTrue);
      expect(model.canOfferCoinVideo, isFalse);
      final saved = await store.load();
      expect((saved['coinOffer'] as Map)['levels'], 7);
      final adFree = AppModel(
        storage: store,
        snapshot: snapshot(7, adFree: true),
        bootTime: () => (boot: 1, milliseconds: now),
      );
      expect(adFree.canOfferCoinVideo, isFalse);
      model.dispose();
      adFree.dispose();
    },
  );

  test(
    'insufficient balance and failed persistence do not issue duplicate debits',
    () async {
      final store = MemoryStorage();
      final model = AppModel(storage: store, snapshot: {});
      expect(await model.buyTip(PathTip.arrow), isFalse);
      expect(model.coinBalance, 50);
      expect(model.ownsTip(PathTip.arrow), isFalse);
      model.dispose();
      final rich = AppModel(
        storage: store,
        snapshot: {
          'ledger': [
            {
              'id': 'starter',
              'label': 'Welcome',
              'amount': 150,
              'at': '2026-01-01T00:00:00Z',
            },
          ],
        },
      );
      store.fail = true;
      expect(await rich.buyTip(PathTip.arrow), isFalse);
      expect(rich.storageError, isTrue);
      expect(await rich.buyTip(PathTip.arrow), isFalse);
      expect(rich.coinBalance, 50);
      store.fail = false;
      expect(await rich.flush(), isTrue);
      final restored = AppModel(storage: store, snapshot: await store.load());
      expect(restored.ownsTip(PathTip.arrow), isTrue);
      expect(restored.coinBalance, 50);
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
        3,
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
      final card = find.byKey(const ValueKey('tip-card-arrow'));
      await tester.tap(
        find.descendant(of: card, matching: find.byType(TipArtwork)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Up'), findsOneWidget);
      await tester.tap(find.text('Up'));
      await tester.pump();
      expect(model.equippedTip, PathTip.classic);
      final preview = tester.widget<LevelOneBoardPreview>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(LevelOneBoardPreview),
        ),
      );
      expect(preview.tip, PathTip.arrow);
      expect(preview.directionOverride, 3);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      ads.dispose();
      billing.dispose();
    });
  }
}
