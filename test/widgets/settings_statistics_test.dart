import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/logic/billing_service.dart';
import 'package:pathwise/logic/sound_service.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/user_preferences.dart';
import 'package:pathwise/views/main_menu_view.dart';
import 'package:pathwise/views/settings_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets(
    'Settings omits reward information and retains management entries',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final model = AppModel(storage: MemoryStorage(), snapshot: {});
      final ads = AdService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            ChangeNotifierProvider.value(value: ads),
          ],
          child: const MaterialApp(home: SettingsView()),
        ),
      );
      expect(find.text('Reward information'), findsNothing);
      expect(find.text('Haptic feedback'), findsOneWidget);
      expect(find.text('Google Play Achievements'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.text('Ad privacy'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await model.flush();
      model.dispose();
      ads.dispose();
    },
  );
}
