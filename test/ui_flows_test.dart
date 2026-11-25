import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/main.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/economy.dart';
import '../lib/model/user_preferences.dart';
import '../lib/ui/game_ui.dart';
import '../lib/views/components/tip_art.dart';
import '../lib/views/store_view.dart';
import 'app_model_test.dart' show MemoryStorage;

void main() {
  testWidgets('home has a full-width Store card and no bag or Themes tile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = AppModel(storage: MemoryStorage(), snapshot: {});
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: model, child: const PathwiseApp()),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('store-card'));
    expect(card, findsOneWidget);
    expect(find.byTooltip('Store'), findsNothing);
    expect(find.text('Themes'), findsNothing);
    final cardWidth = tester.getSize(card).width;
    final wheel = find.byKey(const ValueKey('wheel-tile'));
    await tester.scrollUntilVisible(wheel, 100);
    expect(cardWidth, tester.getSize(wheel).width);
    expect(cardWidth, greaterThan(300));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(StoreView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('Coins and Upgrades stay visible without billing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
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
    await tester.tap(find.text('Coins'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('free-coins')), findsOneWidget);
    expect(
      find.text('Purchases are unavailable on this build.'),
      findsOneWidget,
    );
    // Packs are shown with an unavailable price, never an invented one.
    expect(find.text('Unavailable'), findsWidgets);
    expect(find.text('500'), findsOneWidget);
    await tester.tap(find.text('Upgrades'));
    await tester.pumpAndSettle();
    for (final title in ['Premium', 'Themes Forever', 'Remove Ads']) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    ads.dispose();
    billing.dispose();
  });

  test('every paid tip keeps its price and the catalogue has 20 tips', () {
    expect(PathTip.values.length, 20);
    expect(PathTip.classic.price, 0);
    for (final tip in PathTip.values.where((t) => t != PathTip.classic)) {
      expect({120, 250, 500, 900}, contains(tip.price), reason: tip.label);
    }
  });

  testWidgets('every tip paints upright on every theme without errors', (
    tester,
  ) async {
    for (final palette in BoardPalette.palettes.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(
            children: [
              for (final tip in PathTip.values)
                SizedBox.square(
                  dimension: 64,
                  child: TipArtwork(tip: tip, palette: palette),
                ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('price pills show only a coin and a number', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: PricePill(price: 100, onTap: () {})),
        ),
      ),
    );
    expect(find.text('100'), findsOneWidget);
    expect(find.byType(CoinMark), findsOneWidget);
    expect(find.textContaining('coins'), findsNothing);
  });
}
