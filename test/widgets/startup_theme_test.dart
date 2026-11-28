import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/main.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/app_themes.dart';
import 'package:pathwise/model/user_preferences.dart';

import '../support/fixtures.dart';

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
