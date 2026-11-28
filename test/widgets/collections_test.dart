import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/logic/billing_service.dart';
import 'package:pathwise/logic/connectivity_service.dart';
import 'package:pathwise/logic/game_state_storage.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/economy.dart';
import 'package:pathwise/model/user_preferences.dart';
import 'package:pathwise/views/journey_rewards.dart';
import 'package:provider/provider.dart';

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
}
