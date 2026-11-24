import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/game_controller.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/user_preferences.dart';
import '../lib/views/components/puzzle_board.dart';
import '../lib/views/themes_view.dart';
import 'app_model_test.dart' show MemoryStorage;

class _TestBilling extends BillingService {
  _TestBilling() : super(persist: (_) async => true) {
    products.add(
      ProductDetails(
        id: 'pathwise_coins_500',
        title: '500 coins',
        description: '',
        price: '\$1',
        rawPrice: 1,
        currencyCode: 'USD',
      ),
    );
  }
  @override
  bool get enabled => true;
}

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

  testWidgets(
    'pinned preview follows selection but leaving preserves equipped theme',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(storage: MemoryStorage(), snapshot: {});
      final field = BoardPalette.palettes[PathwiseTheme.field]!;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: model,
          child: MaterialApp(
            theme: field.theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const ThemesView()),
                  ),
                  child: const Text('Open themes'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open themes'));
      await tester.pumpAndSettle();
      final preview = find.byType(LevelOneBoardPreview);
      final previewRect = tester.getRect(preview);
      expect(previewRect.top, greaterThanOrEqualTo(0));
      expect(previewRect.bottom, lessThan(640));
      final list = find.byKey(const ValueKey('theme-catalogue'));
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(scrollable);
      final row = find.byKey(const ValueKey('theme-row-midnightSlate'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final offset = state.position.pixels;
      expect(offset, greaterThan(0));
      expect(tester.getRect(preview), previewRect);
      await tester.tap(
        find.descendant(of: row, matching: find.text('Midnight Slate')),
      );
      await tester.pumpAndSettle();
      final midnight = BoardPalette.palettes[PathwiseTheme.midnightSlate]!;
      expect(
        tester.widget<LevelOneBoardPreview>(preview).palette,
        same(midnight),
      );
      expect(
        Theme.of(tester.element(preview)).scaffoldBackgroundColor,
        midnight.canvas,
      );
      expect(state.position.pixels, offset);
      expect(tester.getRect(preview), previewRect);
      expect(tester.widget<ListTile>(row).selected, isTrue);
      final forest = find.byKey(const ValueKey('theme-row-forestMint'));
      final forestTitle = tester.widget<Text>(
        find.descendant(of: forest, matching: find.text('Forest Mint')),
      );
      expect(forestTitle.style!.color, midnight.ink);
      final swatch = tester.widget<CircleAvatar>(
        find.descendant(of: forest, matching: find.byType(CircleAvatar)).first,
      );
      expect(
        swatch.backgroundColor,
        BoardPalette.palettes[PathwiseTheme.forestMint]!.route,
      );
      final price = find.descendant(
        of: forest,
        matching: find.text('90 coins'),
      );
      final ink = tester.widget<Ink>(
        find.ancestor(of: price, matching: find.byType(Ink)).first,
      );
      expect(
        (ink.decoration as ShapeDecoration).color,
        midnight.theme.colorScheme.primary,
      );
      expect(model.theme, PathwiseTheme.field);
      expect(model.ownsTheme(PathwiseTheme.midnightSlate), isFalse);
      expect(model.coinBalance, 50);
      final equipped = find.byKey(const ValueKey('theme-row-field'));
      expect(
        find.descendant(of: equipped, matching: find.text('Equipped')),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(equipped).selected, isFalse);
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .ancestor(
              of: preview,
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      );
      expect(region.value.systemNavigationBarColor, midnight.canvas);
      expect(region.value.systemNavigationBarIconBrightness, Brightness.light);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(model.theme, PathwiseTheme.field);
      expect(
        Theme.of(tester.element(find.text('Open themes')))
            .scaffoldBackgroundColor,
        field.canvas,
      );
      await tester.tap(find.text('Open themes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LevelOneBoardPreview>(find.byType(LevelOneBoardPreview))
            .palette,
        same(field),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    },
  );

  testWidgets('compact preview accommodates large text on a small screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = AppModel(storage: MemoryStorage(), snapshot: {});
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: model,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const ThemesView(),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(LevelOneBoardPreview));
    expect(rect.bottom, lessThan(560));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
  });
  testWidgets(
    'locked theme purchase dialog uses the preview palette and preserves funds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
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
          child: const MaterialApp(home: ThemesView()),
        ),
      );
      final row = find.byKey(const ValueKey('theme-row-forestMint'));
      await tester.ensureVisible(row);
      await tester.tap(
        find.descendant(of: row, matching: find.text('Forest Mint')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.text('90 coins')),
      );
      await tester.pumpAndSettle();
      final dialog = find.text('Not enough coins');
      expect(dialog, findsOneWidget);
      expect(
        Theme.of(tester.element(dialog)).colorScheme.surface,
        BoardPalette.palettes[PathwiseTheme.forestMint]!.surface,
      );
      expect(model.coinBalance, 50);
      expect(model.theme, PathwiseTheme.field);
      expect(model.ownsTheme(PathwiseTheme.forestMint), isFalse);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
      ads.dispose();
      billing.dispose();
    },
  );
  testWidgets(
    'last theme clears the navigation inset with the preview pinned',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = AppModel(storage: MemoryStorage(), snapshot: {});
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: model,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24, bottom: 28),
                viewPadding: const EdgeInsets.only(top: 24, bottom: 28),
              ),
              child: child!,
            ),
            home: const ThemesView(),
          ),
        ),
      );
      final preview = find.byType(LevelOneBoardPreview);
      final position = tester.getRect(preview);
      final last = find.byKey(const ValueKey('theme-row-highPass'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.getRect(preview), position);
      expect(tester.getBottomLeft(last).dy, lessThanOrEqualTo(640 - 28));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
    },
  );

  testWidgets(
    'Canyon preview is restored on back; Apply persists Midnight Slate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = MemoryStorage();
      final model = AppModel(
        storage: storage,
        snapshot: {
          'ownedThemes': ['canyon', 'midnightSlate'],
          'preferences': {'theme': 'canyon'},
        },
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: model,
          child: Consumer<AppModel>(
            builder: (context, player, _) => MaterialApp(
              theme: BoardPalette.palettes[player.theme]!.theme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const ThemesView()),
                    ),
                    child: const Text('Open themes'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> previewMidnight() async {
        final row = find.byKey(const ValueKey('theme-row-midnightSlate'));
        await tester.ensureVisible(row);
        await tester.tap(
          find.descendant(of: row, matching: find.text('Midnight Slate')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<LevelOneBoardPreview>(find.byType(LevelOneBoardPreview))
              .palette,
          same(BoardPalette.palettes[PathwiseTheme.midnightSlate]),
        );
      }

      await tester.tap(find.text('Open themes'));
      await tester.pumpAndSettle();
      await previewMidnight();
      expect(model.theme, PathwiseTheme.canyon);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(model.theme, PathwiseTheme.canyon);
      expect(
        Theme.of(tester.element(find.text('Open themes')))
            .scaffoldBackgroundColor,
        BoardPalette.palettes[PathwiseTheme.canyon]!.canvas,
      );
      await tester.tap(find.text('Open themes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LevelOneBoardPreview>(find.byType(LevelOneBoardPreview))
            .palette,
        same(BoardPalette.palettes[PathwiseTheme.canyon]),
      );
      await previewMidnight();
      final row = find.byKey(const ValueKey('theme-row-midnightSlate'));
      await tester.tap(find.descendant(of: row, matching: find.text('Apply')));
      await tester.pumpAndSettle();
      expect(model.theme, PathwiseTheme.midnightSlate);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Open themes')))
            .scaffoldBackgroundColor,
        BoardPalette.palettes[PathwiseTheme.midnightSlate]!.canvas,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
      final restored = AppModel(
        storage: storage,
        snapshot: await storage.load(),
      );
      expect(restored.theme, PathwiseTheme.midnightSlate);
      restored.dispose();
    },
  );
  testWidgets('Store navigation discards the temporary preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = AppModel(storage: MemoryStorage(), snapshot: {});
    final ads = AdService();
    final billing = _TestBilling();
    final field = BoardPalette.palettes[PathwiseTheme.field]!;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: model),
          ChangeNotifierProvider.value(value: ads),
          ChangeNotifierProvider<BillingService>.value(value: billing),
        ],
        child: MaterialApp(theme: field.theme, home: const ThemesView()),
      ),
    );
    final row = find.byKey(const ValueKey('theme-row-forestMint'));
    await tester.ensureVisible(row);
    await tester.tap(
      find.descendant(of: row, matching: find.text('Forest Mint')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: row, matching: find.text('90 coins')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Coins'));
    await tester.pumpAndSettle();
    expect(find.text('Store'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Store'))).scaffoldBackgroundColor,
      field.canvas,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LevelOneBoardPreview>(find.byType(LevelOneBoardPreview))
          .palette,
      same(field),
    );
    expect(model.coinBalance, 50);
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
    ads.dispose();
    billing.dispose();
  });
}
