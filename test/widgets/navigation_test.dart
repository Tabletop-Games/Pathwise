import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/logic/billing_service.dart';
import 'package:pathwise/main.dart' show PathwiseScrollBehavior;
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/ui/game_ui.dart';
import 'package:pathwise/views/campaign_journey_view.dart';
import 'package:pathwise/views/progression_view.dart';
import 'package:pathwise/views/store_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PathwiseScrollBehavior clamps scrolling and draws no overscroll',
    (tester) async {
      const behavior = PathwiseScrollBehavior();
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(behavior.getScrollPhysics(context), isA<ClampingScrollPhysics>());
      const child = SizedBox();
      expect(
        behavior.buildOverscrollIndicator(
          context,
          child,
          const ScrollableDetails(direction: AxisDirection.down),
        ),
        same(child),
      );
    },
  );

  testWidgets(
    'Journey AppBar title is tappable and Upgrades has no nested tabs',
    (tester) async {
      final model = AppModel(storage: MemoryStorage(), snapshot: {});
      final ads = AdService();
      final billing = BillingService(persist: (_) async => true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppModel>.value(value: model),
            ChangeNotifierProvider<AdService>.value(value: ads),
            ChangeNotifierProvider<BillingService>.value(value: billing),
          ],
          child: const MaterialApp(
            scrollBehavior: PathwiseScrollBehavior(),
            home: CampaignJourneyView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Journey, jump to level 1'), findsOneWidget);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppModel>.value(value: model),
            ChangeNotifierProvider<AdService>.value(value: ads),
            ChangeNotifierProvider<BillingService>.value(value: billing),
          ],
          child: const MaterialApp(home: ProgressionView()),
        ),
      );
      await tester.pump();
      expect(find.byType(GameSegmented<dynamic>), findsNothing);
      expect(find.text('Research'), findsOneWidget);
      expect(find.text('Boosts'), findsOneWidget);
      // All 3 research branches appear as scrolling sections without nested tabs.
      expect(find.text('Research lab'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      ads.dispose();
      billing.dispose();
    },
  );

  testWidgets('Store active-tab reselection scrolls back to top', (
    tester,
  ) async {
    final model = AppModel(storage: MemoryStorage(), snapshot: {});
    final ads = AdService();
    final billing = BillingService(persist: (_) async => true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppModel>.value(value: model),
          ChangeNotifierProvider<AdService>.value(value: ads),
          ChangeNotifierProvider<BillingService>.value(value: billing),
        ],
        child: const MaterialApp(home: StoreView()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const PageStorageKey('store-themes')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(
      find.byKey(const PageStorageKey('store-themes')),
    );
    expect(grid.controller!.offset, greaterThan(0));

    // Tap currently selected 'Themes' tab to scroll back to top.
    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();
    expect(grid.controller!.offset, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    ads.dispose();
    billing.dispose();
  });
}
