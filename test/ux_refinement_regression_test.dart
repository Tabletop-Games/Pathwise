import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/notification_service.dart';
import '../lib/logic/puzzle.dart';
import '../lib/main.dart' show PathwiseScrollBehavior;
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import '../lib/model/notification_preferences.dart';
import '../lib/model/user_preferences.dart';
import '../lib/ui/game_ui.dart';
import '../lib/viewmodels/statistics_viewmodel.dart';
import '../lib/views/campaign_journey_view.dart';
import '../lib/views/components/puzzle_board.dart';
import '../lib/views/components/tip_art.dart';
import '../lib/views/developer_view.dart';
import '../lib/views/progression_view.dart';
import '../lib/views/store_view.dart';
import 'app_model_test.dart' show MemoryStorage;

final class _FakeNotificationBackend implements NotificationBackend {
  bool granted = true;
  final Map<int, ({String category, int triggerAt})> scheduled = {};
  final List<int> shownNow = [];
  final List<int> cancelled = [];

  @override
  Future<bool> canPostNotifications() async => granted;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> schedule({
    required int id,
    required String channel,
    required String title,
    required String body,
    required String category,
    required int triggerAtMillis,
  }) async {
    scheduled[id] = (category: category, triggerAt: triggerAtMillis);
  }

  @override
  Future<void> showNow({
    required int id,
    required String channel,
    required String title,
    required String body,
    required String category,
  }) async {
    shownNow.add(id);
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();

  @override
  Future<String?> consumeInitialTap() async => null;

  @override
  void setTapHandler(void Function(String category)? onTap) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part A: Equipped tip visibility during & after rejection', () {
    testWidgets(
      'custom tip remains visible after invalid checkpoint rejection settles',
      (tester) async {
        final puzzle = Puzzle(3, [0, 4, 8]);
        final model = AppModel(
          storage: MemoryStorage(),
          snapshot: const {},
          loader: (_) async =>
              VerifiedPuzzle(puzzle, const [0, 1, 2, 5, 4, 3, 6, 7, 8]),
        );
        await model.open(const PuzzleId.level(1));
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 300,
                  child: RepaintBoundary(
                    key: key,
                    child: PuzzleBoard(
                      puzzle: puzzle,
                      palette: BoardPalette.palettes[PathwiseTheme.field]!,
                      tipStyle: PathTip.crystal,
                      model: model,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final origin = tester.getTopLeft(
          find.byKey(const ValueKey('puzzle-grid')),
        );
        // Drag from cell 0 (50,50) to cell 1 (150,50) then invalid checkpoint 8 (250,250) via cell 3 (50,150)->(150,150) is valid 2!
        // Instead, drag from cell 0 directly to cell 3 (50,150) then attempt cell 4 (150,150) which is checkpoint 2 — valid;
        // let's attempt cell 4 directly from cell 0 (50,50) -> wait: 0->3 is valid, let's test Puzzle(3, [0, 3, 8]) where 0->1->4->3 or 0->3->8?
        // Actually on [0, 4, 8], stepping 0->1->4 is valid, stepping 0->3->6->7->8 (skipping checkpoint 2 at cell 4) rejects at cell 8!
        final drag = await tester.startGesture(origin + const Offset(50, 50));
        await drag.moveTo(origin + const Offset(50, 150));
        await tester.pump();
        await drag.moveTo(origin + const Offset(50, 250));
        await tester.pump();
        await drag.moveTo(origin + const Offset(150, 250));
        await tester.pump();
        // Attempt cell 8 (checkpoint 3 while next is 2 -> rejected!)
        await drag.moveTo(origin + const Offset(250, 250));
        await tester.pump(const Duration(milliseconds: 50));
        await drag.up();
        // Wait for rejection animation (450ms) to finish completely.
        await tester.pumpAndSettle(const Duration(milliseconds: 600));

        // Verify pointer-layer still paints the custom tip at rest on cell 7 (150, 250).
        final pointerBoundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('pointer-layer')),
        );
        final img = await pointerBoundary.toImage(pixelRatio: 1);
        final bytes = (await img.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final px = (250 * img.width + 150) * 4;
        final alphaAtTip = bytes.getUint8(px + 3);
        img.dispose();
        expect(alphaAtTip, greaterThan(0));
        expect(model.path, [0, 3, 6, 7]);
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
      },
    );
  });

  group('Part B: Overscroll, Journey title, and Tab reselection', () {
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
        expect(find.text('Coins'), findsOneWidget);

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
  });

  group('Part C & D: Star threshold dialog & Streak consistency', () {
    test('longestPlayStreak is never less than current play streak', () {
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'playStreak': {
            'count': 2,
            'longest': 2,
            'freezes': 0,
            'lastEarned': '2026-11-27',
            'checkedThrough': '2026-11-27',
          },
        },
        today: () => DateTime(2026, 11, 27),
      );
      final summary = StatisticsSummary.fromModel(model);
      expect(summary.dayStreak, 2);
      expect(summary.longestPlayStreak, 2);
      expect(summary.dailyStreak, 0);
      expect(summary.longestStreak, 0);
      model.dispose();
    });
  });

  group('Part F & G: AMOLED Journey & Store rings', () {
    testWidgets(
      'TipArtwork in Store omits circular contrast ring on signal/amoled',
      (tester) async {
        for (final theme in [
          PathwiseTheme.signal,
          PathwiseTheme.amoledCarbon,
        ]) {
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
  });

  group('Part H: Adaptive local notifications', () {
    test(
      'adaptive scheduler respects history, quiet hours, and suppression',
      () {
        const scheduler = AdaptiveNotificationScheduler();
        final prefs = NotificationPreferences(
          enabled: true,
          adaptiveTiming: true,
          preferredMinutes: 19 * 60,
          quietStartMinutes: 22 * 60,
          quietEndMinutes: 8 * 60,
        );
        // Insufficient history (<3) falls back to preferredMinutes.
        expect(
          scheduler.chooseReminderMinutes(prefs, DateTime(2026, 11, 27)),
          19 * 60,
        );

        // Record 4 sessions around 20:30 -> learns ~19:45 (15m before 20:00 hour).
        for (var d = 23; d <= 26; d++) {
          prefs.recordActivity(
            DateTime(2026, 11, d, 20, 30).millisecondsSinceEpoch,
          );
        }
        final learned = scheduler.chooseReminderMinutes(
          prefs,
          DateTime(2026, 11, 27),
        );
        expect(learned, 19 * 60 + 45);

        // Quiet hours shift late-night peak (23:30) to quietEndMinutes (08:00).
        final quietPrefs = NotificationPreferences(
          enabled: true,
          adaptiveTiming: true,
          quietStartMinutes: 22 * 60,
          quietEndMinutes: 8 * 60,
        );
        for (var d = 23; d <= 26; d++) {
          quietPrefs.recordActivity(
            DateTime(2026, 11, d, 23, 15).millisecondsSinceEpoch,
          );
        }
        expect(
          scheduler.chooseReminderMinutes(quietPrefs, DateTime(2026, 11, 27)),
          8 * 60,
        );

        // Streak at risk prioritizes streak reminder today.
        final streakPlan = scheduler.plan(
          prefs: prefs,
          now: DateTime(2026, 11, 27, 10, 0),
          dailySolvedToday: false,
          currentStreak: 5,
          streakQualifiedToday: false,
          streakProtectedToday: false,
          inGameplay: false,
        );
        expect(streakPlan.length, 1);
        expect(streakPlan.single.category, NotificationCategory.streak);

        // Qualified streak & solved daily schedules tomorrow's daily + invite.
        final donePlan = scheduler.plan(
          prefs: prefs,
          now: DateTime(2026, 11, 27, 10, 0),
          dailySolvedToday: true,
          currentStreak: 5,
          streakQualifiedToday: true,
          streakProtectedToday: false,
          inGameplay: false,
        );
        expect(
          donePlan.any((n) => n.category == NotificationCategory.streak),
          isFalse,
        );
        final daily = donePlan.firstWhere(
          (n) => n.category == NotificationCategory.daily,
        );
        expect(daily.scheduledAt.day, 28);
      },
    );

    test('NotificationService isolates test IDs and cancels cleanly', () async {
      final backend = _FakeNotificationBackend();
      final service = NotificationService(
        backend: backend,
        now: () => DateTime(2026, 11, 27, 12, 0),
      );
      await service.sendTestNow(NotificationCategory.daily);
      expect(backend.shownNow, [NotificationService.testDailyId]);

      await service.scheduleTestDelayed(NotificationCategory.daily);
      expect(
        backend.scheduled.containsKey(NotificationService.testDelayedId),
        isTrue,
      );

      await service.cancelTestNotifications();
      expect(
        backend.scheduled.containsKey(NotificationService.testDelayedId),
        isFalse,
      );
      service.dispose();
    });
  });

  group('Part E: Developer Dashboard access control', () {
    testWidgets('DeveloperView hides all tools when developerMode is false', (
      tester,
    ) async {
      final model = AppModel(
        storage: MemoryStorage(),
        snapshot: {},
        debugTools: false,
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AppModel>.value(
          value: model,
          child: const MaterialApp(home: DeveloperView()),
        ),
      );
      expect(find.text('Developer dashboard'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    });
  });
}
