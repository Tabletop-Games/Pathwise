import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/connectivity_service.dart';
import '../../lib/model/app_model.dart';
import '../../lib/views/connection_view.dart';
import '../../lib/views/journey_rewards.dart';
import '../../lib/views/puzzle_view.dart';
import '../support/fixtures.dart' show MemoryStorage, fixture;
import '../support/fixtures.dart' show clear, journeyModel;

class _Ads extends AdService {
  bool available = true;
  bool earn = false;
  int presentations = 0;
  int requests = 0;

  @override
  Future<void> prepare({required bool Function() canPresent}) async {
    requests++;
  }

  @override
  bool get enabled => true;

  @override
  bool get videoReady => available;

  @override
  Future<bool> watchVideo(
    Future<bool> Function(String) reward, {
    bool Function()? canPresent,
    RewardPlacement placement = RewardPlacement.coins,
    bool waitForReward = false,
  }) async {
    if (!available || canPresent?.call() == false) return false;
    presentations++;
    if (earn) await reward('sdk-earned');
    return true;
  }
}

void main() {
  testWidgets('no preloaded video still starts and stops the pointer', (
    tester,
  ) async {
    final model = journeyModel(MemoryStorage(), {});
    final ads = _Ads()..available = false;
    final billing = BillingService(persist: (_) async => true);
    await clear(model, 1);
    final normal = model.coinBalance;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppModel>.value(value: model),
          ChangeNotifierProvider<AdService>.value(value: ads),
          ChangeNotifierProvider<BillingService>.value(value: billing),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) =>
                Scaffold(body: CompletionBonus(context.watch<AppModel>())),
          ),
        ),
      ),
    );
    final pointer = find.byKey(const ValueKey('multiplier-pointer'));
    final start = tester.getCenter(pointer);
    await tester.pump(const Duration(milliseconds: 875));
    expect(tester.getCenter(pointer).dx, greaterThan(start.dx));
    expect(ads.requests, 0);
    await tester.tap(find.text('Stop'));
    final position = tester.getCenter(pointer);
    await tester.pumpAndSettle();
    expect(model.selectedMultiplier, 4);
    expect(tester.getCenter(pointer), position);
    final watch = find.textContaining('Watch ad for +24 coins');
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(ads.requests, 1);
    expect(ads.presentations, 0);
    expect(model.coinBalance, normal);
    expect(model.selectedMultiplier, 4);
    expect(
      find.text('Video unavailable. Try again or continue.'),
      findsOneWidget,
    );

    ads.available = true;
    ads.earn = true;
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(ads.presentations, 1);
    expect(model.coinBalance, normal + 24);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    ads.dispose();
    billing.dispose();
  });

  testWidgets(
    'offline results keep the track visible and gate the next puzzle',
    (tester) async {
      var online = true;
      var clock = DateTime(2026, 11, 22);
      final connectivity = ConnectivityService(
        probe: () async => online,
        now: () => clock,
        interval: const Duration(hours: 1),
      );
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        loader: (_) async => fixture(),
        connectivity: connectivity,
      )..setHaptics(false);
      final ads = _Ads()..available = false;
      final billing = BillingService(persist: (_) async => true);
      await connectivity.retry();
      await clear(model, 1);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppModel>.value(value: model),
            ChangeNotifierProvider<AdService>.value(value: ads),
            ChangeNotifierProvider<BillingService>.value(value: billing),
            ChangeNotifierProvider<ConnectivityService>.value(
              value: connectivity,
            ),
          ],
          child: MaterialApp(
            builder: (context, child) =>
                ConnectionGate(connectivity: connectivity, child: child),
            home: const PuzzleView(),
          ),
        ),
      );
      online = false;
      await connectivity.check();
      clock = clock.add(const Duration(seconds: 20));
      await connectivity.check();
      await tester.pump();
      await tester.pump();
      expect(find.text('Reconnect to play the next puzzle.'), findsNothing);
      expect(find.byKey(const ValueKey('pathwise-connection')), findsOneWidget);
      await tester.tap(find.text('Continue playing'));
      await tester.pump();
      expect(find.byKey(const ValueKey('pathwise-connection')), findsNothing);
      final pointer = find.byKey(const ValueKey('multiplier-pointer'));
      final initial = tester.getCenter(pointer);
      await tester.pump(const Duration(milliseconds: 875));
      expect(tester.getCenter(pointer).dx, greaterThan(initial.dx));
      final next = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Next level'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(next.onPressed, isNotNull);
      await tester.ensureVisible(find.text('Stop'));
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(model.selectedMultiplier, isNotNull);
      expect(ads.requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      billing.dispose();
      ads.dispose();
      connectivity.dispose();
    },
  );

  testWidgets('reduced motion keeps fixed offer through cancellation', (
    tester,
  ) async {
    final model = journeyModel(MemoryStorage(), {});
    final ads = _Ads();
    final billing = BillingService(persist: (_) async => true);
    await clear(model, 1);
    final normal = model.coinBalance;
    final watch = find.textContaining('Watch ad for +16 coins');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppModel>.value(value: model),
          ChangeNotifierProvider<AdService>.value(value: ads),
          ChangeNotifierProvider<BillingService>.value(value: billing),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Builder(
                builder: (context) =>
                    CompletionBonus(context.watch<AppModel>()),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Start bonus track'), findsNothing);
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(ads.presentations, 1);
    expect(model.coinBalance, normal);
    ads.earn = true;
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(ads.presentations, 2);
    expect(model.coinBalance, normal + 16);
    expect(watch, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    ads.dispose();
    billing.dispose();
  });

  testWidgets(
    'all five multiplier segments align corner radii and stop accurately',
    (tester) async {
      // Expected stops across the 1750ms half-cycle for [2x, 3x, 4x, 3x, 2x]:
      // 100ms -> ~0.03 (2x left), 550ms -> ~0.29 (3x left), 875ms -> 0.50 (4x),
      // 1200ms -> ~0.71 (3x right), 1650ms -> ~0.97 (2x right).
      final cases = <(int ms, int expectedMult)>[
        (100, 2),
        (550, 3),
        (875, 4),
        (1200, 3),
        (1650, 2),
      ];
      for (final (ms, expected) in cases) {
        final model = journeyModel(MemoryStorage(), {});
        final ads = _Ads();
        final billing = BillingService(persist: (_) async => true);
        await clear(model, 1);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppModel>.value(value: model),
              ChangeNotifierProvider<AdService>.value(value: ads),
              ChangeNotifierProvider<BillingService>.value(value: billing),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) =>
                    Scaffold(body: CompletionBonus(context.watch<AppModel>())),
              ),
            ),
          ),
        );
        final clips = tester
            .widgetList<ClipRRect>(find.byType(ClipRRect))
            .toList();
        // First ClipRRect is the track; next 5 are the segments.
        expect(clips.length, greaterThanOrEqualTo(6));
        final segments = clips.skip(1).take(5).toList();
        expect(
          segments.first.borderRadius,
          const BorderRadius.horizontal(left: Radius.circular(14)),
        );
        for (var i = 1; i <= 3; i++) {
          expect(segments[i].borderRadius, BorderRadius.zero);
        }
        expect(
          segments.last.borderRadius,
          const BorderRadius.horizontal(right: Radius.circular(14)),
        );

        await tester.pump(Duration(milliseconds: ms));
        await tester.tap(find.text('Stop'));
        await tester.pumpAndSettle();
        expect(model.selectedMultiplier, expected);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        ads.dispose();
        billing.dispose();
      }
    },
  );

  testWidgets(
    'all five multiplier segments align corner radii and stop accurately',
    (tester) async {
      // Expected stops across the 1750ms half-cycle for [2x, 3x, 4x, 3x, 2x]:
      // 100ms -> ~0.03 (2x left), 550ms -> ~0.29 (3x left), 875ms -> 0.50 (4x),
      // 1200ms -> ~0.71 (3x right), 1650ms -> ~0.97 (2x right).
      final cases = <(int ms, int expectedMult)>[
        (100, 2),
        (550, 3),
        (875, 4),
        (1200, 3),
        (1650, 2),
      ];
      for (final (ms, expected) in cases) {
        final model = journeyModel(MemoryStorage(), {});
        final ads = _Ads();
        final billing = BillingService(persist: (_) async => true);
        await clear(model, 1);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppModel>.value(value: model),
              ChangeNotifierProvider<AdService>.value(value: ads),
              ChangeNotifierProvider<BillingService>.value(value: billing),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) =>
                    Scaffold(body: CompletionBonus(context.watch<AppModel>())),
              ),
            ),
          ),
        );
        final clips = tester
            .widgetList<ClipRRect>(find.byType(ClipRRect))
            .toList();
        // First ClipRRect is the track; next 5 are the segments.
        expect(clips.length, greaterThanOrEqualTo(6));
        final segments = clips.skip(1).take(5).toList();
        expect(
          segments.first.borderRadius,
          const BorderRadius.horizontal(left: Radius.circular(14)),
        );
        for (var i = 1; i <= 3; i++) {
          expect(segments[i].borderRadius, BorderRadius.zero);
        }
        expect(
          segments.last.borderRadius,
          const BorderRadius.horizontal(right: Radius.circular(14)),
        );

        await tester.pump(Duration(milliseconds: ms));
        await tester.tap(find.text('Stop'));
        await tester.pumpAndSettle();
        expect(model.selectedMultiplier, expected);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        ads.dispose();
        billing.dispose();
      }
    },
  );
}
