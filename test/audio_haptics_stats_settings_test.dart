
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/logic/haptic_service.dart';
import '../lib/logic/sound_service.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/economy.dart';
import '../lib/model/user_preferences.dart';
import '../lib/viewmodels/statistics_viewmodel.dart';
import '../lib/views/main_menu_view.dart';
import '../lib/views/settings_view.dart';
import 'app_model_test.dart' show MemoryStorage;

final class _FakeSoundBackend implements SoundBackend {
  final List<String> played = [];
  final List<double> volumes = [];
  int pauseCalls = 0;
  int resumeCalls = 0;
  int preloadCalls = 0;

  @override
  Future<void> preload(List<String> assets) async {
    preloadCalls++;
  }

  @override
  Future<void> play(
    String asset, {
    required double volume,
    double rate = 1.0,
    int priority = 1,
  }) async {
    played.add(asset);
    volumes.add(volume);
  }

  @override
  Future<void> pauseAll() async => pauseCalls++;

  @override
  Future<void> resumeAll() async => resumeCalls++;

  @override
  Future<void> dispose() async {}
}

final class _FakeHapticBackend implements HapticBackend {
  _FakeHapticBackend({this.supported = true});
  final bool supported;
  final List<HapticKind> fired = [];

  @override
  Future<bool> trigger(HapticKind kind) async {
    if (!supported) return false;
    fired.add(kind);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio & Haptics services', () {
    test(
      'preferences are independent and volume persists across mute',
      () async {
        final storage = MemoryStorage();
        final soundBackend = _FakeSoundBackend();
        final hapticBackend = _FakeHapticBackend();
        final model = AppModel(
          storage: storage,
          snapshot: {},
          sound: SoundService(backend: soundBackend),
          haptic: HapticService(backend: hapticBackend),
        );

        expect(model.soundEnabled, isTrue);
        expect(model.haptics, isTrue);
        expect(model.soundVolume, closeTo(0.75, 1e-9));

        model.setSoundVolume(0.42, preview: true);
        expect(model.soundVolume, closeTo(0.42, 1e-9));
        expect(
          soundBackend.played,
          contains('assets/audio/sfx_checkpoint.wav'),
        );

        model.setSoundEnabled(false);
        expect(model.soundEnabled, isFalse);
        expect(model.haptics, isTrue);
        expect(model.soundVolume, closeTo(0.42, 1e-9));

        final countBefore = soundBackend.played.length;
        model.sound.play(SoundEvent.button);
        expect(soundBackend.played.length, countBefore);

        model.setSoundEnabled(true);
        expect(model.soundEnabled, isTrue);
        expect(model.soundVolume, closeTo(0.42, 1e-9));

        model.setHaptics(false);
        expect(model.haptics, isFalse);
        expect(model.soundEnabled, isTrue);

        await model.flush();
        final restored = AppModel(
          storage: storage,
          snapshot: await storage.load(),
        );
        expect(restored.soundEnabled, isTrue);
        expect(restored.haptics, isFalse);
        expect(restored.soundVolume, closeTo(0.42, 1e-9));

        model.dispose();
        restored.dispose();
      },
    );

    test(
      'rate-limiting, deduplication, lifecycle, and ad suppression work',
      () {
        var now = DateTime(2026, 11, 27, 12, 0, 0);
        final soundBackend = _FakeSoundBackend();
        final hapticBackend = _FakeHapticBackend();
        final sound = SoundService(
          enabled: true,
          volume: 0.8,
          backend: soundBackend,
          now: () => now,
        );
        final haptic = HapticService(
          enabled: true,
          backend: hapticBackend,
          now: () => now,
        );

        // Step cooldown deduplicates rapid bursts.
        sound.play(SoundEvent.step);
        sound.play(SoundEvent.step);
        haptic.trigger(HapticEvent.step);
        haptic.trigger(HapticEvent.step);
        expect(soundBackend.played.length, 1);
        expect(hapticBackend.fired.length, 1);

        // Invalid move deduplicates same gesture token.
        now = now.add(const Duration(milliseconds: 200));
        haptic.trigger(HapticEvent.invalidMove, dedupeToken: (0, 1));
        now = now.add(const Duration(milliseconds: 200));
        haptic.trigger(HapticEvent.invalidMove, dedupeToken: (0, 1));
        expect(hapticBackend.fired.length, 2);

        haptic.resetRejectionDeduplication();
        now = now.add(const Duration(milliseconds: 200));
        haptic.trigger(HapticEvent.invalidMove, dedupeToken: (0, 1));
        expect(hapticBackend.fired.length, 3);

        // Background and ads suppress both audio and haptics.
        sound.setForeground(false);
        haptic.setForeground(false);
        expect(soundBackend.pauseCalls, 1);
        now = now.add(const Duration(seconds: 1));
        sound.play(SoundEvent.coinReward);
        haptic.trigger(HapticEvent.coinReward);
        expect(soundBackend.played.length, 1);
        expect(hapticBackend.fired.length, 3);

        sound.setForeground(true);
        haptic.setForeground(true);
        expect(soundBackend.resumeCalls, 1);

        sound.setAdPlaying(true);
        haptic.setAdPlaying(true);
        now = now.add(const Duration(seconds: 1));
        sound.play(SoundEvent.coinReward);
        haptic.trigger(HapticEvent.coinReward);
        expect(soundBackend.played.length, 1);
        expect(hapticBackend.fired.length, 3);

        sound.setAdPlaying(false);
        haptic.setAdPlaying(false);
        now = now.add(const Duration(seconds: 1));
        sound.play(SoundEvent.coinReward);
        haptic.trigger(HapticEvent.coinReward);
        expect(soundBackend.played.length, 2);
        expect(hapticBackend.fired.length, 4);
      },
    );

    test('unsupported haptic hardware fails gracefully', () {
      final backend = _FakeHapticBackend(supported: false);
      final haptic = HapticService(enabled: true, backend: backend);
      expect(() => haptic.trigger(HapticEvent.puzzleComplete), returnsNormally);
      expect(backend.fired, isEmpty);
      haptic.dispose();
    });
  });

  group('Statistics & Achievements', () {
    test('empty, replay, and large campaign states compute accurately', () {
      final empty = AppModel(storage: MemoryStorage(), snapshot: {});
      final emptySummary = StatisticsSummary.fromModel(empty);
      expect(emptySummary.totalSolved, 0);
      expect(emptySummary.totalStars, 0);
      expect(emptySummary.unlockedAchievements, 0);
      expect(emptySummary.achievements.length, Achievement.values.length);
      empty.dispose();

      // Replay updates best stars without duplicating level count.
      final replay = AppModel(
        storage: MemoryStorage(),
        snapshot: {
          'results': {
            'levels/1': {'milliseconds': 15000, 'hints': 0, 'stars': 2},
            'levels/2': {'milliseconds': 10000, 'hints': 0, 'stars': 3},
            'levels/3': {'milliseconds': 90000, 'hints': 1, 'stars': 0},
          },
        },
      );
      final replaySummary = StatisticsSummary.fromModel(replay);
      expect(replaySummary.levelsSolved, 3);
      expect(replaySummary.totalStars, 5);
      expect(replaySummary.threeStar, 1);
      expect(replaySummary.twoStar, 1);
      expect(replaySummary.oneStar, 0);
      expect(replaySummary.zeroStar, 1);
      replay.dispose();

      // Large campaign (1500 levels) aggregates cleanly without lag.
      final largeResults = <String, dynamic>{
        for (var i = 1; i <= 1500; i++)
          'levels/$i': {
            'milliseconds': 12000,
            'hints': 0,
            'unassisted': true,
            'stars': i % 4,
          },
      };
      final large = AppModel(
        storage: MemoryStorage(),
        snapshot: {'results': largeResults},
      );
      final largeSummary = StatisticsSummary.fromModel(large);
      expect(largeSummary.levelsSolved, 1500);
      expect(
        largeSummary.threeStar +
            largeSummary.twoStar +
            largeSummary.oneStar +
            largeSummary.zeroStar,
        1500,
      );
      large.dispose();
    });
  });

  group('Settings & Statistics UI', () {
    testWidgets(
      'SettingsView and StatisticsView render cleanly across themes and scaling',
      (tester) async {
        final soundBackend = _FakeSoundBackend();
        final model = AppModel(
          storage: MemoryStorage(),
          snapshot: {
            'results': {
              'levels/1': {'milliseconds': 12000, 'hints': 0, 'stars': 3},
            },
          },
          sound: SoundService(backend: soundBackend),
        );
        final ads = AdService();
        final billing = BillingService(persist: (_) async => true);

        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final theme in [
          PathwiseTheme.field,
          PathwiseTheme.blackwater,
          PathwiseTheme.amoledCarbon,
          PathwiseTheme.signal,
        ]) {
          model.setTheme(theme);
          final callsBefore = soundBackend.played.length;
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AppModel>.value(value: model),
                ChangeNotifierProvider<AdService>.value(value: ads),
                ChangeNotifierProvider<BillingService>.value(value: billing),
              ],
              child: MaterialApp(
                theme: BoardPalette.palettes[theme]!.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!,
                ),
                home: const SettingsView(),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('Audio & feedback'), findsOneWidget);
          expect(find.text('Sound effects'), findsOneWidget);
          expect(find.text('Sound volume'), findsOneWidget);
          expect(find.text('Haptic feedback'), findsOneWidget);
          expect(find.byType(Slider), findsOneWidget);
          // Rebuilds must not replay sounds.
          expect(soundBackend.played.length, callsBefore);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AppModel>.value(value: model),
                ChangeNotifierProvider<AdService>.value(value: ads),
                ChangeNotifierProvider<BillingService>.value(value: billing),
              ],
              child: MaterialApp(
                theme: BoardPalette.palettes[theme]!.theme,
                home: const StatisticsView(),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(ExpansionTile), findsNothing);
          expect(find.text('Campaign performance'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Pathwise Achievements'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Pathwise Achievements'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        // Home screen has Settings icon button.
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppModel>.value(value: model),
              ChangeNotifierProvider<AdService>.value(value: ads),
              ChangeNotifierProvider<BillingService>.value(value: billing),
            ],
            child: const MaterialApp(home: MainMenuView()),
          ),
        );
        await tester.pump();
        expect(find.byTooltip('Settings'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        ads.dispose();
        billing.dispose();
      },
    );
  });
}
