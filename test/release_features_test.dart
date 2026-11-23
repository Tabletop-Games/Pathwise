import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:material_ui/material_ui.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/puzzle_generator.dart';
import '../lib/logic/puzzle_solver.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/economy.dart';
import '../lib/model/game_state.dart';
import '../lib/model/user_preferences.dart';
import 'app_model_test.dart' show MemoryStorage, complete, fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final day = DateTime(2026, 11, 22);
  AppModel create(
    MemoryStorage store, [
    Map<String, dynamic> saved = const {},
  ]) => AppModel(
    storage: store,
    snapshot: saved,
    today: () => day,
    loader: (_) async => fixture(),
  )..setHaptics(false);

  test('early, boundary and very high levels are deterministic and unique', () {
    for (final number in [1, 12, 36, 37, 100, 150, 500, 1000, 1000000]) {
      final id = PuzzleId.level(number);
      final board = generatePuzzle(id.generation);
      expect(solve(board.puzzle).unique, isTrue, reason: 'level $number');
      expect(board.solution.toSet().length, board.puzzle.area);
      expect(board.solution.first, board.puzzle.start);
      expect(board.solution.last, board.puzzle.finish);
      expect(
        generatePuzzle(id.generation).puzzle.checkpoints,
        board.puzzle.checkpoints,
      );
      expect(
        firstLevelOnPage(pageForLevel(number)),
        inInclusiveRange(number - 11, number),
      );
    }
    expect(pageForLevel(12), 0);
    expect(pageForLevel(13), 1);
  });

  test('later difficulty bands target and produce longer deductions on a 7×7 board', () {
    expect(const PuzzleId.level(37).size, const PuzzleId.level(1000).size);
    expect(
      const PuzzleId.level(37).generation.clues,
      greaterThan(const PuzzleId.level(1000).generation.clues),
    );
    double averageClues(int start) =>
        List.generate(
          12,
          (i) =>
              generatePuzzle(PuzzleId.level(start + i).generation)
                  .puzzle
                  .checkpoints
                  .length,
        ).reduce((left, right) => left + right) /
        12;
    expect(averageClues(1000), lessThan(averageClues(37)));
  });

  test('level unlock, achievement and reward are durably idempotent including replay', () async {
    final store = MemoryStorage();
    final model = create(store);
    await model.open(const PuzzleId.level(2));
    expect(model.activeId, isNull);
    await model.open(const PuzzleId.level(1));
    complete(model);
    expect(model.highestUnlocked, 2);
    expect(model.lastReward, 32);
    expect(model.coinBalance, 72);
    expect(model.hasAchievement(Achievement.trailhead), isTrue);
    await model.open(const PuzzleId.level(1), replay: true);
    complete(model);
    expect(model.lastReward, 0);
    expect(model.coinBalance, 72);
    expect(model.levelsSolved, 1);
    await model.flush();
    final restored = create(store, await store.load());
    expect(restored.highestUnlocked, 2);
    expect(restored.coinBalance, 72);
    expect(
      restored.transactions.where((tx) => tx.id == 'achievement/trailhead'),
      hasLength(1),
    );
    model.dispose();
    restored.dispose();
  });

  test('v1 migration preserves unlocked legacy gaps, attempts, times, and equipped theme', () async {
    final store = MemoryStorage();
    final model = create(store, {
      'results': {
        'levels/36': {'milliseconds': 60000, 'hints': 1},
        'daily/2026-11-20': {'milliseconds': 50000, 'hints': 0},
        'daily/2026-11-21': {'milliseconds': 49000, 'hints': 0},
        'endless/1': {'milliseconds': 12000, 'hints': 0},
      },
      'preferences': {'theme': 'terracotta', 'haptics': false},
      'attempts': {
        'levels/14': {
          'milliseconds': 3000,
          'hints': 0,
          'path': [0, 1, 2],
          'history': [
            [0],
          ],
          'started': true,
        },
      },
    });
    expect(model.highestUnlocked, 37);
    expect(model.levelsSolved, 1);
    expect(model.theme, PathwiseTheme.terracotta);
    expect(model.ownedThemes, 3);
    expect(model.result(const PuzzleId.level(36))!.milliseconds, 60000);
    expect(model.longestStreak, 2);
    expect(model.endless.value, 2);
    expect(model.playTime.inMilliseconds, 171000);
    await model.open(const PuzzleId.level(14));
    expect(model.path, [0, 1, 2]);
    model.close();
    await model.flush();
    final snapshot = await store.load();
    expect(snapshot['schemaVersion'], 4);
    final restored = create(store, snapshot);
    expect(restored.coinBalance, economy.starterCoins);
    expect(restored.highestUnlocked, 37);
    expect(restored.hasAttempt(const PuzzleId.level(14)), isTrue);
    model.dispose();
    restored.dispose();
  });

  test(
    'verified grant and theme purchase cannot double credit or debit',
    () async {
      final store = MemoryStorage();
      final model = create(store);
      expect(model.unlockTheme(PathwiseTheme.forestMint), isFalse);
      expect(
        await model.applyVerifiedPurchase('grant-a', coins: 120, themes: false),
        isTrue,
      );
      expect(
        await model.applyVerifiedPurchase('grant-a', coins: 120, themes: false),
        isTrue,
      );
      expect(model.coinsEarned, 160);
      expect(model.unlockTheme(PathwiseTheme.forestMint), isTrue);
      expect(model.unlockTheme(PathwiseTheme.forestMint), isFalse);
      expect(model.coinBalance, 50);
      expect(model.coinsSpent, 110);
      await model.flush();
      final restored = create(store, await store.load());
      expect(restored.ownsTheme(PathwiseTheme.forestMint), isTrue);
      expect(restored.theme, PathwiseTheme.forestMint);
      expect(restored.coinBalance, 50);
      expect(
        await restored.applyVerifiedPurchase(
          'grant-a',
          coins: 120,
          themes: false,
        ),
        isTrue,
      );
      expect(restored.coinBalance, 50);
      expect(
        await restored.applyVerifiedPurchase(
          'grant-pass',
          coins: 0,
          themes: true,
        ),
        isTrue,
      );
      expect(restored.ownedThemes, PathwiseTheme.values.length);
      expect(restored.hasAchievement(Achievement.collector), isTrue);
      model.dispose();
      restored.dispose();
    },
  );

  test('optional ads are disabled by default and video ids and daily caps are enforced', () async {
    final ads = AdService();
    expect(ads.enabled, isFalse);
    expect(ads.videoReady, isFalse);
    await ads.prepare(canPresent: () => true);
    ads.afterCompletedExit(canPresent: true);
    expect(
      AdService.validAdUnit('ca-app-pub-3940256099942544/1033173712'),
      isFalse,
    );
    ads.dispose();

    final model = create(MemoryStorage());
    expect(await model.grantAdBonus('first'), isTrue);
    expect(await model.grantAdBonus('first'), isFalse);
    expect(await model.grantAdBonus('second'), isTrue);
    expect(await model.grantAdBonus('third'), isTrue);
    expect(await model.grantAdBonus('fourth'), isFalse);
    expect(model.coinBalance, 64);
    model.dispose();
  });

  test('billing outcomes are fail closed and finalize after verification and durable save', () async {
    final calls = <String>[];
    Future<BillingOutcome> process(
      PurchaseStatus status, {
      bool verified = true,
      bool saved = true,
    }) => processPurchase(
      status: status,
      verify: () async {
        calls.add('verify');
        return verified ? (id: 'grant', product: themePassProduct) : null;
      },
      persist: (_) async {
        calls.add('persist');
        return saved;
      },
      finalize: () async {
        calls.add('finalize');
      },
    );

    expect(await process(PurchaseStatus.pending), BillingOutcome.pending);
    expect(await process(PurchaseStatus.canceled), BillingOutcome.canceled);
    expect(await process(PurchaseStatus.error), BillingOutcome.rejected);
    expect(calls, isEmpty);
    expect(
      await process(PurchaseStatus.purchased, verified: false),
      BillingOutcome.rejected,
    );
    expect(calls, ['verify']);
    calls.clear();
    expect(
      await process(PurchaseStatus.purchased, saved: false),
      BillingOutcome.retry,
    );
    expect(calls, ['verify', 'persist']);
    calls.clear();
    expect(await process(PurchaseStatus.restored), BillingOutcome.complete);
    expect(calls, ['verify', 'persist', 'finalize']);
  });

  test(
    'daily streak bonuses and milestones persist once across a seven-day run',
    () async {
      var now = DateTime(2026, 11, 16);
      final store = MemoryStorage();
      final model = AppModel(
        storage: store,
        snapshot: {},
        today: () => now,
        loader: (_) async => fixture(),
      )..setHaptics(false);
      for (var index = 0; index < 7; index++) {
        now = DateTime(2026, 11, 16 + index);
        await model.open(model.daily);
        complete(model);
      }
      expect(model.dailyStreak, 7);
      expect(model.longestStreak, 7);
      expect(model.lastReward, 24 + 35 + 45);
      final balance = model.coinBalance;
      await model.open(model.daily, replay: true);
      complete(model);
      expect(model.lastReward, 0);
      expect(model.coinBalance, balance);
      await model.flush();
      final restored = create(store, await store.load());
      expect(restored.longestStreak, 7);
      expect(restored.hasAchievement(Achievement.weeklyRitual), isTrue);
      expect(
        restored.transactions.where((item) => item.id.startsWith('streak/')),
        hasLength(1),
      );
      model.dispose();
      restored.dispose();
    },
  );

  test('theme foregrounds meet 4.5:1 against their paired surfaces', () {
    double contrast(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    for (final theme in PathwiseTheme.values) {
      final palette = BoardPalette.palettes[theme]!;
      for (final (foreground, background) in [
        (palette.ink, palette.surface),
        (palette.muted, palette.canvas),
        (palette.onRoute, palette.route),
        (palette.onAccent, palette.accent),
      ]) {
        expect(
          contrast(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: theme.label,
        );
      }
    }
  });
}
