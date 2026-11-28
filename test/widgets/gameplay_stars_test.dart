import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/ad_service.dart';
import 'package:pathwise/logic/billing_service.dart';
import 'package:pathwise/logic/puzzle.dart';
import 'package:pathwise/logic/star_rating.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/game_state.dart';
import 'package:pathwise/ui/game_ui.dart';
import 'package:pathwise/views/puzzle_view.dart';
import 'package:provider/provider.dart';

import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'Part F: Star depletion bar, immediate timer, and simplified completion',
    () {
      test(
        'starDepletionProgress maps thresholds piecewise to star positions',
        () {
          const thresholds = StarThresholds(
            threeStarMs: 10000,
            twoStarMs: 20000,
            oneStarMs: 30000,
            multiplier: 1.0,
          );
          expect(starDepletionProgress(0, thresholds), 1.0);
          expect(
            starDepletionProgress(thresholds.threeStarMs, thresholds),
            closeTo(0.84, 1e-6),
          );
          expect(
            starDepletionProgress(thresholds.twoStarMs, thresholds),
            closeTo(0.50, 1e-6),
          );
          expect(
            starDepletionProgress(thresholds.oneStarMs, thresholds),
            closeTo(0.16, 1e-6),
          );
          expect(
            starDepletionProgress(thresholds.oneStarMs + 2000, thresholds),
            0.0,
          );
          expect(
            starDepletionProgress(5000, thresholds),
            greaterThan(starDepletionProgress(15000, thresholds)),
          );
          expect(
            starDepletionProgress(15000, thresholds),
            greaterThan(starDepletionProgress(25000, thresholds)),
          );
        },
      );

      test(
        'timer starts immediately on open when no tutorial is pending',
        () async {
          final app = AppModel(
            storage: MemoryStorage(),
            snapshot: {},
            loader: (_) async => VerifiedPuzzle(Puzzle(3, [0, 2, 4, 8]), [
              0,
              1,
              2,
              5,
              4,
              3,
              6,
              7,
              8,
            ]),
          );
          app.setForeground(true);
          await app.open(PuzzleId.level(1));
          expect(app.loading, isFalse);
          expect(app.elapsed.value.inMilliseconds, lessThan(100));

          await Future<void>.delayed(const Duration(milliseconds: 260));
          expect(app.elapsed.value.inMilliseconds, greaterThanOrEqualTo(200));
          app.dispose();
        },
      );

      testWidgets(
        'PuzzleView shows star depletion bar and simplified completion screen',
        (tester) async {
          const solution = [0, 1, 2, 5, 4, 3, 6, 7, 8];
          final app = AppModel(
            storage: MemoryStorage(),
            snapshot: {'unlocked': 2, 'onboardingDone': true},
            loader: (_) async =>
                VerifiedPuzzle(Puzzle(3, [0, 2, 4, 8]), solution),
          );
          app.setForeground(true);
          await app.open(PuzzleId.level(1));

          final ads = AdService();
          final billing = BillingService(persist: (_) async => true);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AppModel>.value(value: app),
                ChangeNotifierProvider<AdService>.value(value: ads),
                ChangeNotifierProvider<BillingService>.value(value: billing),
              ],
              child: MaterialApp(
                theme: ThemeData.light(),
                home: const PuzzleView(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.bySemanticsLabel(RegExp(r'\d+ of 3 stars available')),
            findsOneWidget,
          );
          expect(find.byType(RatingStar), findsNWidgets(3));
          expect(find.byType(LinearProgressIndicator), findsNothing);

          app.begin(solution.first);
          for (final cell in solution.skip(1)) {
            app.step(cell);
          }
          app.end();
          await tester.pump(const Duration(milliseconds: 600));

          expect(find.text('Level complete!'), findsOneWidget);
          expect(find.textContaining('target:'), findsNothing);
          expect(find.textContaining('0 hints'), findsNothing);
          expect(find.textContaining('star bonus'), findsNothing);
          expect(find.text('Next level'), findsOneWidget);
          expect(find.text('Replay'), findsOneWidget);
          expect(find.text('Return to Levels'), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          app.dispose();
          ads.dispose();
          billing.dispose();
        },
      );
    },
  );
}
