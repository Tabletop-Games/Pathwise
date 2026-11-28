import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/logic/connectivity_service.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/economy.dart';
import 'package:pathwise/model/progression.dart';
import 'package:pathwise/ui/game_ui.dart';
import 'package:pathwise/views/progression_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

class _BoostAds extends AdService {
  bool available = false;
  bool earnsReward = false;
  int requests = 0;
  int presentations = 0;

  @override
  bool get enabled => true;

  @override
  bool readyFor(RewardPlacement placement) => available;

  @override
  Future<void> prepare({required bool Function() canPresent}) async {
    requests++;
  }

  @override
  Future<bool> watchVideo(
    Future<bool> Function(String) reward, {
    bool Function()? canPresent,
    RewardPlacement placement = RewardPlacement.coins,
    bool waitForReward = false,
  }) async {
    expect(placement, RewardPlacement.boost);
    if (!available || canPresent?.call() == false) return false;
    presentations++;
    if (earnsReward) await reward('video-$presentations');
    return true;
  }
}

Future<void> _openBoosts(
  WidgetTester tester,
  AppModel model,
  AdService ads,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider<AdService>.value(value: ads),
      ],
      child: const MaterialApp(home: ProgressionView(boosts: true)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _shop(Boost boost) => find.byKey(ValueKey('boost-shop-${boost.name}'));

Finder _inventory(Boost boost) =>
    find.byKey(ValueKey('boost-inventory-${boost.name}'));

Finder _action(Finder row, String label) =>
    find.descendant(of: row, matching: find.widgetWithText(ActionPill, label));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.hitTestable(), 140);
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shop shows discounted prices and durations at large text', (
    tester,
  ) async {
    final connectivity = ConnectivityService(probe: () async => false);
    final model = AppModel(
      storage: MemoryStorage(),
      connectivity: connectivity,
      snapshot: {
        'archivedCoins': 28,
        'preferences': {'theme': 'amoledCarbon'},
        'ownedThemes': ['amoledCarbon'],
        'progression': {
          'ranks': {'savings': 6, 'efficiency': 5, 'tuning': 2},
        },
      },
    );
    final ads = AdService();
    await connectivity.retry();
    expect(model.onlineReady, isFalse);
    await _openBoosts(tester, model, ads);
    expect(find.text('No boosts in your inventory'), findsOneWidget);
    expect(find.text('Boost Shop'), findsOneWidget);
    expect(find.text('Active boosts'), findsNothing);

    final quickCharge = _shop(Boost.doubleTen);
    expect(
      find.descendant(of: quickCharge, matching: find.text('2× · 5m 36s')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quickCharge, matching: find.byType(ActionPill)),
      findsNothing,
    );
    final price = find.descendant(
      of: quickCharge,
      matching: find.byType(PricePill),
    );
    expect(
      tester.widget<PricePill>(price).semanticLabel,
      'Buy Quick Charge for 57 coins',
    );
    await _tapVisible(tester, price);
    expect(find.text('29 short'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(model.coinBalance, 28);
    expect(_inventory(Boost.doubleTen), findsNothing);
    await tester.scrollUntilVisible(
      _shop(Boost.quadrupleTen).hitTestable(),
      140,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await model.flush();
    model.dispose();
    ads.dispose();
    connectivity.dispose();
  });

  testWidgets(
    'offline buying and activating update inventory, restrictions and timer',
    (tester) async {
      var clock = 100;
      final connectivity = ConnectivityService(probe: () async => false);
      final model = AppModel(
        storage: MemoryStorage(),
        connectivity: connectivity,
        bootTime: () => (boot: 1, milliseconds: clock),
        snapshot: {
          'archivedCoins': 70,
          'progressionBoot': 1,
          'progression': {
            'inventory': {'doubleTen': 1},
          },
        },
      );
      final ads = AdService();
      await connectivity.retry();
      expect(model.onlineReady, isFalse);
      await _openBoosts(tester, model, ads);
      final quickCharge = _inventory(Boost.doubleTen);
      final price = find.descendant(
        of: _shop(Boost.doubleTen),
        matching: find.byType(PricePill),
      );
      await _tapVisible(tester, price);
      expect(model.coinBalance, 10);
      await tester.scrollUntilVisible(quickCharge.hitTestable(), -150);
      expect(
        find.descendant(of: quickCharge, matching: find.text('2 owned')),
        findsOneWidget,
      );

      await tester.tap(_action(quickCharge, 'Activate'));
      await tester.pumpAndSettle();
      expect(find.text('2× Quick Charge'), findsOneWidget);
      expect(find.text('5 min left'), findsOneWidget);
      expect(
        find.descendant(of: quickCharge, matching: find.text('1 owned')),
        findsOneWidget,
      );
      expect(
        tester.widget<ActionPill>(_action(quickCharge, 'Activate')).onTap,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Active boosts').hitTestable(),
        -150,
      );
      clock += const Duration(minutes: 1, seconds: 1).inMilliseconds;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('3m 59s left'), findsOneWidget);
      clock += const Duration(minutes: 4).inMilliseconds;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2× Quick Charge'), findsNothing);
      expect(
        tester.widget<ActionPill>(_action(quickCharge, 'Activate')).onTap,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
      ads.dispose();
      connectivity.dispose();
    },
  );

  testWidgets(
    'videos honor readiness, earned callbacks and daily eligibility',
    (tester) async {
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        today: () => DateTime(2026, 11, 25),
      );
      final ads = _BoostAds();
      await _openBoosts(tester, model, ads);
      final quick = _shop(Boost.doubleTen);
      final power = _shop(Boost.tripleFifteen);
      expect(
        tester.widget<ActionPill>(_action(power, 'Video locked')).onTap,
        isNull,
      );
      Finder watch(Finder row) => _action(row, 'Watch');

      await _tapVisible(tester, watch(quick));
      expect(find.text('Video unavailable'), findsOneWidget);
      expect(ads.requests, 1);
      expect(ads.presentations, 0);
      expect(_inventory(Boost.doubleTen), findsNothing);

      ads.available = true;
      await _tapVisible(tester, watch(quick));
      expect(ads.presentations, 1);
      expect(_inventory(Boost.doubleTen), findsNothing);

      ads.earnsReward = true;
      for (var video = 0; video < 4; video++) {
        await _tapVisible(tester, watch(quick));
      }
      expect(
        find.descendant(
          of: _inventory(Boost.doubleTen),
          matching: find.text('4 owned'),
        ),
        findsOneWidget,
        reason: 'Quick Charge videos are not capped',
      );
      for (var i = 0; i < economy.coinAdMilestone; i++) {
        await model.grantAdBonus('coin-video-$i');
      }
      await tester.pumpAndSettle();
      await _tapVisible(tester, watch(power));
      expect(
        tester.widget<ActionPill>(_action(power, 'Daily limit')).onTap,
        isNull,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
      ads.dispose();
    },
  );
}
