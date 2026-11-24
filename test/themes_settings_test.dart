import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lib/logic/ad_service.dart';
import '../lib/model/app_model.dart';
import '../lib/views/settings_view.dart';
import 'app_model_test.dart' show MemoryStorage;

void main() {
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
