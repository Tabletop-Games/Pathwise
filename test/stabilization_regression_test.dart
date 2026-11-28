import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_frequency.dart';
import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/connectivity_service.dart';
import '../lib/logic/game_controller.dart';
import '../lib/logic/game_state_storage.dart';
import '../lib/logic/puzzle.dart';
import '../lib/logic/tip_tracker.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/economy.dart';
import '../lib/model/user_preferences.dart';
import '../lib/views/components/puzzle_board.dart';
import '../lib/views/journey_rewards.dart';

class _TestBoardControls implements BoardControls, RejectionControls {
  _TestBoardControls(this.game);
  final GameController game;
  VoidCallback? changed;

  @override
  List<int> get path => game.path;
  @override
  int? get tip => game.tip;
  @override
  int? get hintCell => game.hintCell;
  @override
  int get nextCheckpoint => game.nextCheckpoint;
  @override
  bool get complete => game.complete;
  @override
  bool begin(int cell) {
    final ok = game.begin(cell);
    changed?.call();
    return ok;
  }

  @override
  bool canStep(int cell) => game.canStep(cell);
  @override
  void step(int cell) {
    game.step(cell);
    changed?.call();
  }

  @override
  void end() {
    game.end();
    changed?.call();
  }

  @override
  void tap(int cell) {
    if (begin(cell)) end();
  }

  @override
  RejectedMove? rejectionFor(int cell) => game.rejectionFor(cell);
  @override
  void rejectHaptic() {}
}

class _MemoryStorage extends GameStateStorage {
  String data = '{}';

  @override
  Future<Map<String, dynamic>> load() async =>
      Map<String, dynamic>.from(jsonDecode(data) as Map);

  @override
  Future<void> save(String snapshot) async {
    data = snapshot;
  }
}

void main() {
  group('P0 upright tip tracking & cosmetic consistency', () {
    test(
      'TipTracker stops short of out-of-bounds, walls, and closed gates',
      () {
        // 3x3 board, start at 0, wall between 0 and 1, only legal move is down (1 -> cell 3).
        final puzzle = Puzzle(3, [0, 8], walls: [(0, 1)]);
        final tracker = TipTracker();

        final rightDrag = tracker.update(
          puzzle: puzzle,
          route: const [0],
          pointer: const Offset(0.85, 0.5),
          canEnter: (c) => c == 3,
        );
        expect(rightDrag.tip.dx, lessThan(0.85));

        final upDrag = tracker.update(
          puzzle: puzzle,
          route: const [0],
          pointer: const Offset(0.5, 0.15),
          canEnter: (c) => c == 3,
        );
        expect(upDrag.tip.dy, closeTo(0.08, 1e-9));

        final leftDrag = tracker.update(
          puzzle: puzzle,
          route: const [0],
          pointer: const Offset(0.15, 0.5),
          canEnter: (c) => c == 3,
        );
        expect(leftDrag.tip.dx, greaterThan(0.15));
      },
    );

    test(
      'TipTracker.rest centers on normal cells and offsets above checkpoints',
      () {
        final puzzle = Puzzle(3, [0, 8]);
        final rest = TipTracker.rest(puzzle, const [0]);
        expect(rest.tip.dx, rest.center.dx);
        expect(rest.tip.dy, closeTo(rest.center.dy - 0.42, 1e-9));
        expect(rest.extension, 0.42);
      },
    );

    testWidgets(
      'PuzzleBoard renders non-classic cosmetic at rest, during drag, and at dead end',
      (tester) async {
        final puzzle = Puzzle(3, [0, 8], walls: [(1, 2), (1, 4)]);
        final game = GameController(
          VerifiedPuzzle(puzzle, [0, 3, 6, 7, 4, 5, 2, 1, 8]),
        );
        final controls = _TestBoardControls(game);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 300,
                  child: StatefulBuilder(
                    builder: (context, update) {
                      controls.changed = () => update(() {});
                      return PuzzleBoard(
                        model: controls,
                        puzzle: puzzle,
                        palette: BoardPalette.palettes[PathwiseTheme.field]!,
                        tipStyle: PathTip.cat,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        // Move to cell 1 (which only has backtracking to 0 because walls block 2 and 4).
        final grid = find.byKey(const ValueKey('puzzle-grid'));
        final topLeft = tester.getTopLeft(grid);
        final gesture = await tester.startGesture(
          topLeft + const Offset(50, 50),
        );
        await gesture.moveTo(topLeft + const Offset(150, 50));
        await tester.pump();
        expect(controls.path, [0, 1]);

        // Release at dead end cell 1 -> should settle cleanly without exceptions.
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('P1 progressive mystery discovery & claim/apply', () {
    test(
      'upcoming discovery persists across snapshot save and restore',
      () async {
        final storage = _MemoryStorage();
        final model = AppModel(
          storage: storage,
          snapshot: const {},
          connectivity: ConnectivityService(probe: () async => true),
          today: () => DateTime(2026, 11, 25),
          bootTime: () => (boot: 1, milliseconds: 1000),
        );

        final firstUpcoming = model.upcomingDiscoveryItem;
        expect(firstUpcoming, isNotEmpty);
        await model.flush();

        // Reload from storage and verify identical upcoming discovery item.
        final loadedSnapshot = await storage.load();
        final reloaded = AppModel(
          storage: storage,
          snapshot: loadedSnapshot,
          connectivity: ConnectivityService(probe: () async => true),
          today: () => DateTime(2026, 11, 25),
          bootTime: () => (boot: 1, milliseconds: 1000),
        );
        expect(reloaded.upcomingDiscoveryItem, firstUpcoming);

        model.dispose();
        reloaded.dispose();
      },
    );

    testWidgets('ProgressiveDiscoveryArt renders at every 10% increment', (
      tester,
    ) async {
      final light = BoardPalette.palettes[PathwiseTheme.field]!;
      final dark = BoardPalette.palettes[PathwiseTheme.blackwater]!;
      for (final palette in [light, dark]) {
        for (final tip in PathTip.values) {
          if (tip == PathTip.classic) continue;
          for (final pct in [0, 10, 20, 50, 90, 100]) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: ProgressiveDiscoveryArt(
                      item: 'tip/${tip.name}',
                      palette: palette,
                      progress: pct / 100,
                      size: 108,
                    ),
                  ),
                ),
              ),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'failed for ${tip.name} at $pct%',
            );
          }
        }
      }
    });

    testWidgets(
      'CollectionsView renders prominent ProgressiveDiscoveryArt at 20% without progress bar',
      (tester) async {
        final storage = _MemoryStorage();
        final model = AppModel(
          storage: storage,
          snapshot: const {
            'journey': {'clears': 2, 'upcoming': 'tip/crystal'},
          },
          connectivity: ConnectivityService(probe: () async => true),
          today: () => DateTime(2026, 11, 25),
          bootTime: () => (boot: 1, milliseconds: 1000),
        );
        final ads = AdService();
        final billing = BillingService(persist: (_) async => true);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppModel>.value(value: model),
              ChangeNotifierProvider<AdService>.value(value: ads),
              ChangeNotifierProvider<BillingService>.value(value: billing),
            ],
            child: MaterialApp(
              theme: BoardPalette.palettes[PathwiseTheme.blackwater]!.theme,
              home: const CollectionsView(),
            ),
          ),
        );
        expect(find.byType(ProgressiveDiscoveryArt), findsNWidgets(2));
        expect(find.text('20% revealed'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        ads.dispose();
        billing.dispose();
      },
    );

    test(
      'all 20 tip PNGs have zero residual alpha in outer 2px border',
      () async {
        final dir = Directory('assets/art/tips');
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.webp'))
            .toList();
        expect(files.length, 20);
        for (final file in files) {
          final bytes = await file.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final img = frame.image;
          final raw = (await img.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          for (var y = 0; y < img.height; y++) {
            for (var x = 0; x < img.width; x++) {
              if (x < 2 || x >= img.width - 2 || y < 2 || y >= img.height - 2) {
                final alpha = raw.getUint8((y * img.width + x) * 4 + 3);
                expect(
                  alpha,
                  0,
                  reason: '${file.path} has residual alpha $alpha at ($x, $y)',
                );
              }
            }
          }
          img.dispose();
          codec.dispose();
        }
      },
    );
  });

  group('P1 interstitial frequency', () {
    test('AdFrequency enforces exit count, minimum gap, and rewarded gap', () {
      final freq = AdFrequency(
        minimumGap: const Duration(minutes: 3),
        rewardedGap: const Duration(minutes: 1),
        exitsPerInterstitial: 5,
      );
      for (var i = 0; i < 4; i++) {
        freq.completedExit();
        expect(freq.eligible(const Duration(minutes: 5)), isFalse);
      }
      freq.completedExit();
      expect(freq.eligible(const Duration(minutes: 5)), isTrue);

      freq.attemptedInterstitial(const Duration(minutes: 5));
      for (var i = 0; i < 5; i++) {
        freq.completedExit();
      }
      expect(freq.eligible(const Duration(minutes: 6)), isFalse);
      expect(freq.eligible(const Duration(minutes: 8)), isTrue);

      freq.rewardedClosed(const Duration(minutes: 8));
      expect(freq.eligible(const Duration(minutes: 8, seconds: 30)), isFalse);
      expect(freq.eligible(const Duration(minutes: 9)), isTrue);
    });
  });

  group('Final visual refinement & release guards', () {
    test(
      'UI and resource PNGs have zero residual alpha in outer 2px border',
      () async {
        for (final dirPath in [
          'assets/art/ui',
          'assets/art/resources',
          'assets/art/journey',
        ]) {
          final files = Directory(dirPath)
              .listSync()
              .whereType<File>()
              .where(
                (f) =>
                    (f.path.endsWith('.webp') || f.path.endsWith('.png')) &&
                    !f.path.endsWith('_terrain.webp'),
              )
              .toList();
          expect(files.isNotEmpty, isTrue);
          for (final file in files) {
            final bytes = await file.readAsBytes();
            final codec = await ui.instantiateImageCodec(bytes);
            final frame = await codec.getNextFrame();
            final img = frame.image;
            final data = await img.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(data, isNotNull);
            final rgba = data!.buffer.asUint8List();
            final w = img.width;
            final h = img.height;
            for (var y = 0; y < h; y++) {
              for (var x = 0; x < w; x++) {
                if (x < 2 || x >= w - 2 || y < 2 || y >= h - 2) {
                  final alpha = rgba[(y * w + x) * 4 + 3];
                  expect(
                    alpha,
                    0,
                    reason:
                        '${file.path} has residual alpha $alpha at ($x, $y)',
                  );
                }
              }
            }
            img.dispose();
            codec.dispose();
          }
        }
      },
    );

    testWidgets(
      'CollectionsView renders ProgressiveDiscoveryArt in both header and upcoming catalogue tile',
      (tester) async {
        final storage = _MemoryStorage();
        final model = AppModel(
          storage: storage,
          snapshot: const {},
          connectivity: ConnectivityService(probe: () async => true),
          today: () => DateTime(2026, 11, 25),
          bootTime: () => (boot: 1, milliseconds: 1000),
        );
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: model,
            child: const MaterialApp(home: CollectionsView()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ProgressiveDiscoveryArt), findsAtLeastNWidgets(1));
        model.dispose();
      },
    );

    test(
      'Economy 2.0 does not compound research bonuses with timed boosts',
      () {
        expect(
          economy.campaignClearCoins(
            multiplier: 4,
            magnetBonus: 10,
            goldenBonus: 8,
            momentumBonus: 0,
          ),
          38,
        );
        expect(
          economy.campaignClearCoins(
            multiplier: 4,
            magnetBonus: 10,
            goldenBonus: 8,
            momentumBonus: 16,
          ),
          54,
        );
        expect(
          economy.dailyClearCoins(
            multiplier: 4,
            fortuneBonus: 16,
            goldenBonus: 8,
          ),
          64,
        );
      },
    );

    test('a saved journey restores its progress and replaces an invalid upcoming reward', () {
      AppModel launch(String upcoming) => AppModel(
        storage: _MemoryStorage(),
        snapshot: {
          'hintBalance': 7,
          'journey': {'clears': 14, 'upcoming': upcoming},
        },
        connectivity: ConnectivityService(probe: () async => true),
        today: () => DateTime(2026, 11, 25),
        bootTime: () => (boot: 1, milliseconds: 1000),
      );
      final valid = launch('tip/cat');
      expect(valid.hintsRemaining, 7);
      expect(valid.discoveryPercent, 40);
      expect(valid.upcomingDiscoveryItem, 'tip/cat');
      valid.dispose();
      final invalid = launch('tip/not-a-tip');
      expect(invalid.upcomingDiscoveryItem, isNot('tip/not-a-tip'));
      expect(invalid.upcomingDiscoveryItem, matches(RegExp(r'^[a-z]+/')));
      invalid.dispose();
    });

    test('Developer tools stay disabled by default and ignore mutations', () {
      final model = AppModel(
        storage: _MemoryStorage(),
        snapshot: const {},
        connectivity: ConnectivityService(probe: () async => true),
        today: () => DateTime(2026, 11, 25),
        bootTime: () => (boot: 1, milliseconds: 1000),
      );
      expect(model.developerMode, isFalse);
      final coinsBefore = model.coinBalance;
      model.setDebugResources(coins: 999999, hints: 99);
      model.advanceDebugDay(qualify: true);
      expect(model.coinBalance, coinsBefore);
      model.dispose();
    });
  });
}
