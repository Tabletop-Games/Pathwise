import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../lib/cloud/cloud_save_format.dart';
import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/puzzle_generator.dart';
import '../../lib/logic/star_rating.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/game_state.dart';
import '../../lib/ui/art/game_assets.dart';
import '../../lib/views/components/tip_art.dart';
import '../../lib/views/main_menu_view.dart';
import '../support/fixtures.dart' show MemoryStorage, complete, fixture;

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
