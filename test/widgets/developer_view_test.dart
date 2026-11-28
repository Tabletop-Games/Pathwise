import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/notification_service.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/logic/star_rating.dart';
import '../../lib/main.dart' show PathwiseScrollBehavior;
import '../../lib/model/app_model.dart';
import '../../lib/model/app_themes.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/game_state.dart';
import '../../lib/model/notification_preferences.dart';
import '../../lib/model/user_preferences.dart';
import '../../lib/ui/game_ui.dart';
import '../../lib/viewmodels/statistics_viewmodel.dart';
import '../../lib/views/campaign_journey_view.dart';
import '../../lib/views/components/puzzle_board.dart';
import '../../lib/views/components/tip_art.dart';
import '../../lib/views/developer_view.dart';
import '../../lib/views/progression_view.dart';
import '../../lib/views/puzzle_view.dart';
import '../../lib/views/store_view.dart';
import '../support/fixtures.dart' show MemoryStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DeveloperView hides all tools when developerMode is false', (
    tester,
  ) async {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {},
      debugTools: false,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: const MaterialApp(home: DeveloperView()),
      ),
    );
    expect(find.text('Developer dashboard'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });
}
