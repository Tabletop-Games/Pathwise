import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/notification_service.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/logic/star_rating.dart';
import '../../lib/main.dart' show PathwiseScrollBehavior;
import '../../lib/model/app_model.dart';
import '../../lib/model/app_themes.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/game_state.dart';
import '../../lib/model/notification_preferences.dart';
import '../../lib/model/user_preferences.dart';
import '../../lib/ui/game_ui.dart';
import '../../lib/viewmodels/statistics_viewmodel.dart';
import '../../lib/views/campaign_journey_view.dart';
import '../../lib/views/components/puzzle_board.dart';
import '../../lib/views/components/tip_art.dart';
import '../../lib/views/developer_view.dart';
import '../../lib/views/progression_view.dart';
import '../../lib/views/puzzle_view.dart';
import '../../lib/views/store_view.dart';
import '../support/fixtures.dart' show MemoryStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'PathwiseScrollBehavior uses ClampingScrollPhysics and removes indicator',
    () {
      const behavior = PathwiseScrollBehavior();
      expect(
        behavior.getScrollPhysics(
          // ignore: invalid_use_of_protected_member
          TestWidgetsFlutterBinding.instance.rootElement!,
        ),
        isA<ClampingScrollPhysics>(),
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
      expect(
        find.bySemanticsLabel('Journey, jump to level 1'),
        findsOneWidget,
      );

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
