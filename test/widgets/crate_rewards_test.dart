import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/game_state.dart';
import '../../lib/model/progression.dart';
import '../../lib/views/puzzle_view.dart';
import '../support/fixtures.dart' show MemoryStorage, complete, fixture;

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
}
