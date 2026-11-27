import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/model/app_model.dart';
import '../lib/model/game_state.dart';
import '../lib/model/native_achievements.dart';
import '../lib/model/progression.dart';
import '../lib/model/time_attack.dart';
import '../lib/model/user_preferences.dart';
import '../lib/views/puzzle_view.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

class CrateAds extends AdService {
  int attempts = 0;
  @override
  bool readyFor(RewardPlacement placement) => true;

  @override
  Future<bool> watchVideo(
    Future<bool> Function(String) reward, {
    bool Function()? canPresent,
    RewardPlacement placement = RewardPlacement.coins,
    bool waitForReward = false,
  }) async {
    expect(placement, RewardPlacement.crate);
    expect(waitForReward, true);
    attempts++;
    if (attempts == 1) return false;
    if (attempts == 2) return true;
    expect(await reward('verified-crate'), true);
    expect(await reward('verified-crate'), false);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crate odds, cooldown and rolling cap', () {
    expect(
      List.generate(100, crateCoins).where((coins) => coins == 20).length,
      35,
    );
    expect(
      List.generate(100, crateCoins).where((coins) => coins == 35).length,
      30,
    );
    expect(
      List.generate(100, crateCoins).where((coins) => coins == 55).length,
      20,
    );
    expect(
      List.generate(100, crateCoins).where((coins) => coins == 75).length,
      10,
    );
    expect(
      List.generate(100, crateCoins).where((coins) => coins == 90).length,
      5,
    );
    final progress = Progression({});
    expect(progress.considerCrate((boot: 1, milliseconds: 0), () => 0), isNull);
    progress.accrueCrateTime(45000);
    for (var i = 0; i < 8; i++) {
      final now = (boot: 1, milliseconds: 45000 + i * 150000);
      expect(progress.considerCrate(now, () => 0)?.coins, 20);
      expect(progress.considerCrate(now, () => 0), isNull);
      progress.accrueCrateTime(150000);
    }
    expect(
      Progression(progress.toJson())
          .considerCrate((boot: 2, milliseconds: 100), () => 0),
      isNull,
    );
  });

  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets(
      'floating layout, input, completion, retry and exactly-once claim at ${width}dp',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final store = MemoryStorage();
        final ads = CrateAds();
        final billing = BillingService(persist: (_) async => true);
        addTearDown(billing.dispose);
        var ms = 100;
        final model = AppModel(
          storage: store,
          snapshot: {},
          loader: (_) async => fixture(),
          bootTime: () => (boot: 1, milliseconds: ms),
        )..setHaptics(false);
        await model.open(const PuzzleId.level(1));
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: model),
              ChangeNotifierProvider<AdService>.value(value: ads),
              ChangeNotifierProvider<BillingService>.value(value: billing),
            ],
            child: const MaterialApp(home: PuzzleView()),
          ),
        );
        model.tap(1);
        await tester.pumpAndSettle();
        final catchCrate = find.byTooltip('Catch supply crate');
        Future<void> drop(int seconds) async {
          ms += seconds * 1000;
          await tester.pump(Duration(seconds: seconds));
          await tester.pump();
        }

        final board = find.byKey(const ValueKey('puzzle-grid'));
        final progress = find.bySemanticsLabel(
          RegExp(r'\d+ of 3 stars available'),
        );
        final boardRect = tester.getRect(board);
        final barRect = tester.getRect(progress);
        expect(barRect.width, closeTo((width - 32).clamp(0, 490), .1));
        await drop(44);
        expect(catchCrate, findsNothing);
        await drop(1);
        final first = tester.getCenter(catchCrate);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.getCenter(catchCrate).dy, greaterThan(first.dy));
        expect(tester.getRect(catchCrate).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(catchCrate).right, lessThanOrEqualTo(width));
        expect(tester.getRect(board), boardRect);
        expect(tester.getRect(progress), barRect);
        final next =
            boardRect.topLeft +
            Offset(boardRect.width * 5 / 6, boardRect.height / 6);
        expect(tester.getRect(catchCrate).contains(next), false);
        await tester.tapAt(next);
        await tester.pump();
        expect(model.path.last, 2);
        final boardAfterMove = tester.getRect(board);
        final barAfterMove = tester.getRect(progress);
        await tester.pump(const Duration(seconds: 2));
        expect(
          tester.getCenter(catchCrate).dy,
          inInclusiveRange(boardAfterMove.top, boardAfterMove.bottom),
        );
        await tester.pump(const Duration(seconds: 5));
        expect(catchCrate, findsNothing);
        expect(tester.getRect(board), boardAfterMove);
        expect(tester.getRect(progress), barAfterMove);
        expect(model.coinBalance, 50);
        await drop(150);
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(catchCrate);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(model.coinBalance, 50);
        await drop(150);
        final crate = model.fallingCrate!;
        final amount = crate.coins;
        await tester.pump(const Duration(seconds: 2));
        complete(model);
        await tester.pump();
        expect(model.complete, isTrue);
        expect(model.fallingCrate, crate);
        // Crate persists on completion (position may shift slightly as the
        // AppBar is hidden on completion, expanding the body layout).
        expect(catchCrate, findsOneWidget);
        final beforeClaim = model.coinBalance;
        Future<void> finishDialogAnimation() async {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
        }

        await tester.tap(catchCrate);
        await finishDialogAnimation();
        expect(find.text('+$amount'), findsOneWidget);
        expect(catchCrate, findsNothing);
        for (final feedback in [
          'Video unavailable. Try again.',
          'Video ended without a reward. Try again.',
        ]) {
          await tester.tap(find.text('Watch'));
          await finishDialogAnimation();
          expect(find.text(feedback), findsOneWidget);
          expect(model.coinBalance, beforeClaim);
        }
        await tester.tap(find.text('Watch'));
        await finishDialogAnimation();
        expect(find.text('Watch'), findsNothing);
        expect(
          model.transactions
              .singleWhere((entry) => entry.id == 'crate-ad/verified-crate')
              .amount,
          amount,
        );
        expect(model.fallingCrate, isNull);
        expect(
          (await store.load())['progression'].containsKey('crates'),
          false,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        model.dispose();
        ads.dispose();
      },
    );
  }

  test('legacy saves preserve balances, completed puzzles, earned themes and one-time refunds', () async {
    final store = MemoryStorage();
    const BootTime stamp = (boot: 7, milliseconds: 150000);
    Map<String, Object> transaction(String id, String label, int amount) => {
      'id': id,
      'label': label,
      'amount': amount,
      'at': '2026-11-23T12:00:00Z',
    };
    AppModel launch(Map<String, dynamic> snapshot) =>
        AppModel(storage: store, snapshot: snapshot, bootTime: () => stamp);
    var model = launch({
      'schemaVersion': 8,
      'archivedTrailCoins': 1000,
      'ledger': [
        transaction('trail/1/3', 'Old trail', 12),
        transaction('notes/week/12', 'Old objective', 64),
        transaction('research/fieldwork/0', 'Fieldwork', -210),
        transaction('boost/10', '50% more first-qualification base coins', -12),
      ],
      'expeditionProgress': {
        'next': 4,
        'stages': 5,
        'clean': 1,
        'qualifiedClean': 26,
      },
      'expedition': {'obsolete': 'intentionally unreadable'},
      'fieldNotes': {'obsolete': 'ignored'},
      'highestUnlocked': 71,
      'hintTank': 2,
      'ownedThemes': ['basinGold'],
      'preferences': {'theme': 'basinGold'},
      'attempts': {'expedition/10/2/0': {}, 'levels/71': {}},
      'results': {
        'levels/70': {'milliseconds': 500, 'hints': 0},
      },
      'progressionBoot': 6,
      'progression': {
        'serial': 12,
        'ranks': {'expedition': 3, 'fieldwork': 1, 'hunter': 3},
        'inventory': {'trailProvisions': 1, 'doubleTen': 1},
        'crate': {
          'id': 'crate/11',
          'coins': 55,
          'rarity': 'rare',
          'deadline': 100,
        },
      },
    });
    expect(model.coinBalance, 1076);
    expect(model.highestUnlocked, 71);
    expect(model.result(const PuzzleId.level(70))?.milliseconds, 500);
    expect(model.hintsRemaining, 2);
    expect(model.theme, PathwiseTheme.basinGold);
    expect(model.solved, 33);
    expect(model.unassisted, 28);
    expect(model.progression.ranks, {'hunter': 3});
    expect(model.achievementCounters[AchievementMetric.research], 7);
    expect(model.progression.inventory, {'doubleTen': 1});
    expect(model.fallingCrate, isNull);
    expect(await model.flush(), true);
    model.dispose();

    final saved = await store.load();
    expect(saved.keys, isNot(contains('expedition')));
    expect(saved.keys, isNot(contains('fieldNotes')));
    expect(saved['attempts'].keys, ['levels/71']);
    model = launch(saved);
    expect(model.coinBalance, 1076);
    expect(model.solved, 33);
    expect(model.fallingCrate, isNull);
    expect(saved['progression'].containsKey('crates'), false);
    model.dispose();
  });
}
