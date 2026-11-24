import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/logic/billing_service.dart';
import '../lib/model/app_model.dart';
import '../lib/views/journey_rewards.dart';
import 'app_model_test.dart' show MemoryStorage;
import 'journey_test.dart' show clear, journeyModel;

class _Ads extends AdService {
  bool available = true;
  bool earn = false;
  int presentations = 0;

  @override
  bool get enabled => true;

  @override
  bool get videoReady => available;

  @override
  Future<bool> watchVideo(
    Future<bool> Function(String) reward, {
    bool Function()? canPresent,
    RewardPlacement placement = RewardPlacement.coins,
    bool waitForReward = false,
  }) async {
    if (!available || canPresent?.call() == false) return false;
    presentations++;
    if (earn) await reward('sdk-earned');
    return true;
  }
}

void main() {
  testWidgets('reduced motion keeps fixed offer through cancellation', (
    tester,
  ) async {
    final model = journeyModel(MemoryStorage(), {});
    final ads = _Ads();
    final billing = BillingService(persist: (_) async => true);
    await clear(model, 1);
    final normal = model.coinBalance;
    final watch = find.textContaining('Watch for +10 coins');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppModel>.value(value: model),
          ChangeNotifierProvider<AdService>.value(value: ads),
          ChangeNotifierProvider<BillingService>.value(value: billing),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Builder(
                builder: (context) =>
                    CompletionBonus(context.watch<AppModel>()),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Start bonus track'), findsNothing);
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(ads.presentations, 1);
    expect(model.coinBalance, normal);
    ads.earn = true;
    await tester.tap(watch);
    await tester.pumpAndSettle();
    expect(ads.presentations, 2);
    expect(model.coinBalance, normal + 10);
    expect(watch, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    ads.dispose();
    billing.dispose();
  });
}
