import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/logic/billing_service.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/economy.dart';
import 'package:pathwise/ui/art/game_assets.dart';
import 'package:pathwise/views/components/tip_art.dart';
import 'package:pathwise/views/main_menu_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

AppModel _model(MemoryStorage storage, Map<String, dynamic> snapshot) =>
    AppModel(
      storage: storage,
      snapshot: snapshot,
      loader: (_) async => fixture(),
      bootTime: () => (boot: 1, milliseconds: 100),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cosmetic tip artwork & rendering specs', () {
    test('every tip resolves to its own artwork file', () {
      expect(tipAssetPath(PathTip.classic), 'assets/art/tips/classic.webp');
      expect(tipAssetPath(PathTip.robot), 'assets/art/tips/robot.webp');
      for (final tip in PathTip.values) {
        expect(tipAssetPath(tip), 'assets/art/tips/${tip.name}.webp');
      }
    });

    test('all tip specs are upright with positive scale', () {
      for (final tip in PathTip.values) {
        expect(tipSpecFor(tip).scale, greaterThan(0));
      }
      expect(PathTip.values.length, 19);
    });

    testWidgets(
      'Home screen renders Compass artwork when Compass is equipped',
      (tester) async {
        final model = _model(MemoryStorage(), {});
        final ads = AdService();
        final billing = BillingService(persist: (_) async => true);
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
        final images = tester
            .widgetList<Image>(find.byType(Image))
            .map((w) => w.image)
            .whereType<AssetImage>()
            .map((a) => a.assetName)
            .toList();
        expect(images, contains('assets/art/tips/classic.webp'));
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        ads.dispose();
        billing.dispose();
      },
    );
  });
}
