import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/views/developer_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

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
