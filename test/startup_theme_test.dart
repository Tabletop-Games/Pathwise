import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../lib/main.dart';
import '../lib/model/app_model.dart';
import '../lib/model/app_themes.dart';
import '../lib/model/user_preferences.dart';
import 'app_model_test.dart' show MemoryStorage;

void main() {
  testWidgets('saved palette colors startup until the home screen opens', (
    tester,
  ) async {
    const theme = PathwiseTheme.blackwater;
    final startup = Completer<AppModel>();
    final model = AppModel(
      snapshot: {
        'preferences': {'theme': theme.name},
      },
      storage: MemoryStorage(),
    );
    await tester.pumpWidget(
      PathwiseStartup(theme: theme, initialize: () => startup.future),
    );
    final splash = find.byKey(const ValueKey('pathwise-splash'));
    expect(
      tester.widget<Scaffold>(splash).backgroundColor,
      BoardPalette.palettes[theme]!.canvas,
    );
    startup.complete(model);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    expect(splash, findsNothing);
    expect(find.byType(PathwiseApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
