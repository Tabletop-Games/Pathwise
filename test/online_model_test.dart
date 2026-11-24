import 'package:flutter_test/flutter_test.dart';

import '../lib/logic/puzzle.dart';
import '../lib/model/app_model.dart';
import '../lib/model/economy.dart';
import '../lib/model/fortune.dart';
import '../lib/model/game_state.dart';
import '../lib/model/progression.dart';
import '../lib/model/user_preferences.dart';
import 'app_model_test.dart' show MemoryStorage;
import 'support/fake_gateway.dart';

VerifiedPuzzle board() =>
    VerifiedPuzzle(Puzzle(3, [0, 2, 4, 8]), [0, 1, 2, 5, 4, 3, 6, 7, 8]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGateway gateway;
  late MemoryStorage store;
  setUp(() {
    gateway = FakeGateway();
    store = MemoryStorage();
  });

  AppModel launch({Map<String, dynamic> snapshot = const {}}) {
    final model = AppModel(
      storage: store,
      snapshot: Map.of(snapshot),
      today: () => DateTime(2026, 11, 22),
      loader: (_) async => board(),
      bootTime: () => (boot: 1, milliseconds: 100000),
      online: gateway,
    )..setHaptics(false);
    gateway.onWallet = model.applyWallet;
    return model;
  }

  void solve(AppModel model) {
    final route = board().solution;
    model.begin(route.first);
    for (final cell in route.skip(1)) {
      model.step(cell);
    }
    model.end();
  }

  test('the server wallet replaces a locally edited save', () async {
    final model = launch(
      snapshot: {
        'schemaVersion': 13,
        'ledger': [
          {'id': 'hacked', 'label': 'x', 'amount': 999999, 'at': '2026-11-01T00:00:00Z'},
        ],
        'hintBalance': 500,
        'removeAds': true,
        'premium': true,
        'ownedThemes': ['gilded', 'neon'],
      },
    );
    model.applyServerState({'wallet': serverWallet(), 'progress': <String, dynamic>{}});
    expect(model.coinBalance, 50);
    expect(model.hintsRemaining, 3);
    expect(model.adFree, isFalse);
    expect(model.premium, isFalse);
    expect(model.ownsTheme(PathwiseTheme.gilded), isFalse);
    model.dispose();
  });

  test('a refunded balance shown by the server can be negative', () {
    final model = launch();
    model.applyWallet(serverWallet(coins: -450));
    expect(model.coinBalance, -450);
    expect(model.unlockTheme(PathwiseTheme.forestMint), isFalse);
    model.dispose();
  });

  test('ad-free entitlements come from the server', () async {
    final model = launch();
    model.applyWallet(serverWallet(themePass: true));
    expect(model.adFree, isFalse);
    expect(model.ownsTheme(PathwiseTheme.gilded), isTrue);
    model.applyWallet(serverWallet(removeAds: true));
    expect(model.adFree, isTrue);
    expect(await model.reserveAutomaticAd(), isFalse);
    model.applyWallet(serverWallet(premium: true));
    expect(model.adFree, isTrue);
    // Optional rewarded videos remain available to ad-free players.
    expect(model.canEarnAdBonus, isTrue);
    expect(model.canEarnHintAd, isTrue);
    model.dispose();
  });

  test('puzzles cannot be opened while offline', () async {
    gateway.connected = false;
    final model = launch();
    await model.open(const PuzzleId.level(1));
    expect(model.activeId, isNull);
    expect(model.puzzle, isNull);
    model.dispose();
  });

  test('connection loss pauses play and resumes in place', () async {
    final model = launch();
    model.applyWallet(serverWallet());
    await model.open(const PuzzleId.level(1));
    expect(gateway.types, contains('play.start'));
    model.begin(0);
    model.step(1);
    model.step(2);
    // The connection drops in the middle of a stroke.
    gateway.setConnected(false);
    expect(model.isDrawing, isFalse, reason: 'the stroke is finished safely');
    expect(model.path, [0, 1, 2]);
    expect(model.begin(2), isFalse);
    model.step(5);
    expect(model.path, [0, 1, 2], reason: 'input is ignored while paused');
    expect(model.canHint, isFalse);
    model.undo();
    expect(model.path, [0, 1, 2]);
    final pausedAt = model.elapsed.value;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(model.elapsed.value, pausedAt, reason: 'the clock stops');
    // Opening another puzzle is refused.
    await model.open(const PuzzleId.level(2));
    expect(model.activeId, const PuzzleId.level(1));

    gateway.setConnected(true);
    expect(model.begin(2), isTrue);
    model.step(5);
    model.end();
    expect(model.path, [0, 1, 2, 5]);
    model.dispose();
  });

  test('completion is submitted once; hints charge once', () async {
    final model = launch();
    model.applyWallet(serverWallet());
    await model.open(const PuzzleId.level(1));
    model.hint();
    expect(model.hintsRemaining, 2);
    expect(gateway.types.where((t) => t == 'hint.use').length, 1);
    solve(model);
    expect(model.complete, isTrue);
    final completions = gateway.commands.where((c) => c.type == 'play.complete').toList();
    expect(completions.length, 1);
    expect(completions.single.args['key'], 'levels/1');
    expect(completions.single.args['route'], board().solution);
    expect(completions.single.args.containsKey('reward'), isFalse);
    expect(completions.single.args.containsKey('coins'), isFalse);
    model.dispose();
  });

  test('a rejected completion triggers a resync from the server', () async {
    gateway.rejectTypes['play.complete'] = 'invalid_route';
    final model = launch();
    model.applyWallet(serverWallet());
    await model.open(const PuzzleId.level(1));
    solve(model);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.refreshes, greaterThan(0));
    model.dispose();
  });

  test('spends go to the server and are refused offline', () async {
    final model = launch();
    model.applyWallet(serverWallet(coins: 1000));
    expect(model.unlockTheme(PathwiseTheme.forestMint), isTrue);
    expect(gateway.commands.last.type, 'theme.buy');
    expect(gateway.commands.last.args, {'theme': 'forestMint'});
    expect(model.research(Research.magnet), isTrue);
    expect(gateway.commands.last.args, {'item': 'magnet'});
    expect(model.buyBoost(Boost.doubleTen), isTrue);
    expect(await model.buyHint(), isTrue);
    expect(gateway.types.sublist(gateway.types.length - 2), ['boost.buy', 'hint.buy']);

    gateway.setConnected(false);
    final before = gateway.commands.length;
    expect(model.unlockTheme(PathwiseTheme.glacier), isFalse);
    expect(model.research(Research.golden), isFalse);
    expect(model.buyBoost(Boost.doubleTen), isFalse);
    expect(await model.buyHint(), isFalse);
    expect(await model.buyFreeze(), isFalse);
    expect(gateway.commands.length, before);
    model.dispose();
  });

  test('ad rewards are paid only by a verified server claim', () async {
    final model = launch();
    model.applyWallet(serverWallet());
    gateway.wallet = serverWallet(coins: 70);
    expect(await model.grantAdBonus('e' * 64), isTrue);
    expect(gateway.commands.last.type, 'reward.claim');
    expect(model.coinBalance, 70);

    gateway.rewardVerified = false;
    gateway.commands.clear();
    expect(await model.grantHintAd('d' * 64), isFalse);
    expect(gateway.commands, isEmpty, reason: 'nothing is claimed without a signed callback');
    expect(await model.grantAdBonus('short'), isFalse);
    model.dispose();
  });

  test('daily ad limits come from the server, not the device clock', () {
    final model = launch();
    model.applyWallet(serverWallet(limits: const {'coinAds': 0, 'hintAds': 0, 'boostAds': 0}));
    expect(model.canEarnAdBonus, isFalse);
    expect(model.canEarnHintAd, isFalse);
    expect(model.canEarnBoostAd(Boost.doubleTen), isFalse);
    model.dispose();
  });

  test('wheel coins arrive on settle and survive a restart', () async {
    final model = launch();
    model.applyWallet(serverWallet());
    final catalog = FortuneCatalog(
      '[{"id":"sprout","label":"8 coins","weight":30,"coins":8},'
      '{"id":"leaf","label":"15 coins","weight":25,"coins":15},'
      '{"id":"branch","label":"25 coins","weight":20,"coins":25},'
      '{"id":"grove","label":"40 coins","weight":15,"coins":40},'
      '{"id":"ridge","label":"70 coins","weight":8,"coins":70},'
      '{"id":"summit","label":"100 coins","weight":2,"coins":100}]',
    );
    gateway.wallet = serverWallet(pendingWheel: {'id': 'wheel/free/1', 'prize': 'summit'});
    final prize = await model.spinFreeFortune(catalog);
    expect(prize?.id, 'summit');
    expect(model.coinBalance, 50, reason: 'not credited before the animation');
    expect(model.pendingFortune?.id, 'summit');

    // Killed mid-spin: a fresh model restores the pending prize from the server.
    final restarted = launch();
    restarted.applyWallet(serverWallet(pendingWheel: {'id': 'wheel/free/1', 'prize': 'summit'}));
    expect(restarted.pendingFortune?.id, 'summit');

    gateway.wallet = serverWallet(coins: 150);
    expect(await restarted.settleFortune(restarted.pendingFortune!), isTrue);
    expect(gateway.commands.last.type, 'wheel.settle');
    expect(gateway.commands.last.args, {'id': 'wheel/free/1'});
    expect(restarted.coinBalance, 150);
    model.dispose();
    restarted.dispose();
  });

  test('Time Attack uses the server run and reports clears', () async {
    final model = launch();
    model.applyWallet(serverWallet());
    expect(await model.openAttack(), isTrue);
    expect(model.attack?.id, 'v2-serverrun01');
    expect(model.activeId?.key, 'attack/v2-serverrun01/0');
    solve(model);
    final clears = gateway.commands.where((c) => c.type == 'attack.clear').toList();
    expect(clears.single.args['run'], 'v2-serverrun01');
    expect(clears.single.args['route'], board().solution);
    model.stopAttack();
    expect(gateway.types.last, 'attack.stop');
    model.dispose();
  });

  test('server progress restores a new device', () {
    final model = launch();
    model.applyServerState({
      'wallet': serverWallet(),
      'progress': {
        'results': {
          'levels/1': {'ms': 9000, 'hints': 0, 'unassisted': true},
        },
        'stages': <String, dynamic>{},
        'highestUnlocked': 2,
        'tutorials': {'walls': 'completed'},
        'attempts': {
          'levels/2': {
            'v': 3,
            'path': [0, 1],
            'history': <Object>[],
            'hints': 0,
            'hintCell': null,
            'started': true,
            'usedClear': false,
            'ms': 1200,
          },
        },
        'prefs': {'haptics': false, 'suggestSharing': false},
        'attackHistory': <Object>[],
        'attack': null,
      },
    });
    expect(model.result(const PuzzleId.level(1))?.milliseconds, 9000);
    expect(model.highestUnlocked, 2);
    expect(model.canPlayLevel(3), isFalse);
    expect(model.acknowledgedMechanics, contains('walls'));
    expect(model.hasAttempt(const PuzzleId.level(2)), isTrue);
    expect(model.haptics, isFalse);
    expect(model.suggestSharing, isFalse);
    model.dispose();
  });

  test('a local snapshot without a server never pays coins online', () async {
    final model = launch();
    model.applyWallet(serverWallet());
    await model.open(const PuzzleId.level(1));
    solve(model);
    // Local prediction may show a reward, but the next server wallet decides.
    model.applyWallet(serverWallet(coins: 55));
    expect(model.coinBalance, 55);
    expect(economy.clearReward(PlayMode.levels), 5);
    model.dispose();
  });
}
